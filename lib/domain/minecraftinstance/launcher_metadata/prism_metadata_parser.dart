import 'dart:convert';

import '../mod_loader.dart';
import 'instance_metadata.dart';

/// INI 形式(`key=value`)の設定を解析する(011-launcher-instance-discovery.md §6)。
///
/// `prismlauncher.cfg` と `instance.cfg` はいずれもこの形式。セクション見出し
/// (`[General]`)とコメント行は読み飛ばし、キーは元の表記のまま保持する。
/// 壊れた行は無視し、例外を投げない。
Map<String, String> parseIniConfig(String content) {
  final values = <String, String>{};
  for (final rawLine in const LineSplitter().convert(content)) {
    final line = rawLine.trim();
    if (line.isEmpty) continue;
    if (line.startsWith('#') || line.startsWith(';')) continue;
    if (line.startsWith('[') && line.endsWith(']')) continue;

    final separator = line.indexOf('=');
    if (separator <= 0) continue;
    final key = line.substring(0, separator).trim();
    if (key.isEmpty) continue;
    values[key] = line.substring(separator + 1).trim();
  }
  return values;
}

/// `prismlauncher.cfg` の `InstanceDir` を取得する(§6)。
///
/// 未設定・壊れた設定では `null` を返す。相対パスの解決(ランチャールート基準)は
/// infrastructure 層の責務とする。
String? parsePrismInstanceDir(String content) {
  final value = parseIniConfig(content)['InstanceDir']?.trim();
  if (value == null || value.isEmpty) return null;
  return value;
}

/// `{instance}/instance.cfg` からインスタンス名と最終起動日時を取得する(§6)。
///
/// `lastLaunchTime` はミリ秒エポック。解釈できない値は `null` として扱う。
InstanceMetadata parsePrismInstanceCfg(String content) {
  final values = parseIniConfig(content);

  final name = values['name']?.trim();
  final rawLastLaunch = values['lastLaunchTime']?.trim();
  final lastLaunchMillis = rawLastLaunch == null
      ? null
      : int.tryParse(rawLastLaunch);

  return InstanceMetadata(
    name: name != null && name.isNotEmpty ? name : null,
    lastPlayed: lastLaunchMillis != null && lastLaunchMillis > 0
        ? DateTime.fromMillisecondsSinceEpoch(lastLaunchMillis)
        : null,
  );
}

/// `mmc-pack.json` の `components` に現れる `uid` と Mod Loader の対応(§6)。
const Map<String, ModLoader> kPrismComponentLoaders = {
  'net.minecraftforge': ModLoader.forge,
  'net.neoforged': ModLoader.neoForge,
  'net.fabricmc.fabric-loader': ModLoader.fabric,
  'org.quiltmc.quilt-loader': ModLoader.quilt,
};

/// `{instance}/mmc-pack.json` の `components` から Minecraft バージョンと
/// Mod Loader を取得する(§6)。
///
/// 不正 JSON・必須キー欠落では例外を投げず、[InstanceMetadata.empty] 相当を返す。
InstanceMetadata parseMmcPack(String content) {
  final Object? decoded;
  try {
    decoded = jsonDecode(content);
  } catch (_) {
    return InstanceMetadata.empty;
  }
  if (decoded is! Map) return InstanceMetadata.empty;

  final components = decoded['components'];
  if (components is! List) return InstanceMetadata.empty;

  String? minecraftVersion;
  var modLoader = ModLoader.unknown;
  String? modLoaderVersion;

  for (final component in components) {
    if (component is! Map) continue;
    final uid = component['uid'];
    if (uid is! String) continue;
    final version = component['version'];
    final versionText = version is String && version.trim().isNotEmpty
        ? version.trim()
        : null;

    if (uid == 'net.minecraft') {
      minecraftVersion = versionText;
      continue;
    }
    final loader = kPrismComponentLoaders[uid];
    if (loader != null && modLoader == ModLoader.unknown) {
      modLoader = loader;
      modLoaderVersion = versionText;
    }
  }

  // Loader コンポーネントが1件も無い構成は Vanilla とみなす(§6)。
  if (modLoader == ModLoader.unknown && minecraftVersion != null) {
    modLoader = ModLoader.vanilla;
  }

  return InstanceMetadata(
    minecraftVersion: minecraftVersion,
    modLoader: modLoader,
    modLoaderVersion: modLoaderVersion,
  );
}
