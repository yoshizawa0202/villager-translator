import 'dart:convert';

import '../mod_loader.dart';
import 'instance_metadata.dart';

/// `{instance}/minecraftinstance.json` を解析する
/// (011-launcher-instance-discovery.md §7)。
///
/// 不正 JSON・必須キー欠落・型不一致では例外を投げず、読み取れた項目だけを返す。
InstanceMetadata parseCurseForgeInstance(String content) {
  final Object? decoded;
  try {
    decoded = jsonDecode(content);
  } catch (_) {
    return InstanceMetadata.empty;
  }
  if (decoded is! Map) return InstanceMetadata.empty;

  final name = decoded['name'];
  final gameVersion = decoded['gameVersion'];
  final lastPlayed = decoded['lastPlayed'];

  var modLoader = ModLoader.unknown;
  String? modLoaderVersion;

  final baseModLoader = decoded['baseModLoader'];
  if (baseModLoader is Map) {
    // `name` は `forge-47.2.20` のように「Loader 名 + バージョン」を連結した形式。
    final loaderName = baseModLoader['name'];
    if (loaderName is String) {
      final separator = loaderName.indexOf('-');
      if (separator > 0) {
        modLoader = ModLoader.fromName(loaderName.substring(0, separator));
        modLoaderVersion = loaderName.substring(separator + 1).trim();
      } else {
        modLoader = ModLoader.fromName(loaderName);
      }
    }

    final forgeVersion = baseModLoader['forgeVersion'];
    if (forgeVersion is String && forgeVersion.trim().isNotEmpty) {
      modLoaderVersion ??= forgeVersion.trim();
    }
  }

  if (modLoaderVersion != null && modLoaderVersion.isEmpty) {
    modLoaderVersion = null;
  }

  return InstanceMetadata(
    name: name is String && name.trim().isNotEmpty ? name.trim() : null,
    minecraftVersion: gameVersion is String && gameVersion.trim().isNotEmpty
        ? gameVersion.trim()
        : null,
    modLoader: modLoader,
    modLoaderVersion: modLoaderVersion,
    lastPlayed: lastPlayed is String ? DateTime.tryParse(lastPlayed) : null,
  );
}
