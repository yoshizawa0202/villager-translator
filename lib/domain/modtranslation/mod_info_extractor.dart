import 'dart:convert';

import 'mod_info.dart';

/// `fabric.mod.json` の内容から MOD 情報を抽出する。
///
/// `_comment` キーの除去や BOM・制御文字の除去は呼び出し側([lang_codec.dart]
/// と同じ方針)で行う想定だが、本関数自体も壊れた入力に対して例外を投げず
/// `null` を返す(feature-spec.md §6.1: 取得できない MOD はスキップ)。
ModInfo? extractModInfoFromFabricJson(String content) {
  try {
    final decoded = jsonDecode(_stripBom(content));
    if (decoded is! Map<String, dynamic>) return null;

    final id = decoded['id'];
    final version = decoded['version'];
    if (id is! String || id.isEmpty) return null;

    final name = decoded['name'];
    return ModInfo(
      id: id,
      name: name is String && name.isNotEmpty ? name : id,
      version: version is String && version.isNotEmpty ? version : 'unknown',
      source: ModInfoSource.fabricModJson,
    );
  } catch (_) {
    return null;
  }
}

/// `META-INF/mods.toml`(Forge/NeoForge)の内容から MOD 情報を抽出する。
///
/// フル TOML パーサーは用いず、最初の `[[mods]]` テーブルに含まれる
/// `modId` `displayName` `version` の単純なキー = 値行のみを読み取る
/// (本アプリが必要とするのはこの3項目のみのため)。
ModInfo? extractModInfoFromModsToml(String content) {
  final lines = _stripBom(content).split('\n');

  var inModsTable = false;
  String? modId;
  String? displayName;
  String? version;

  for (final rawLine in lines) {
    final line = rawLine.trim();
    if (line.startsWith('[[mods]]')) {
      if (inModsTable) break; // 2つ目の [[mods]] に到達したら最初の要素で確定
      inModsTable = true;
      continue;
    }
    if (!inModsTable) continue;

    if (line.startsWith('[')) break; // 別テーブルへ移行したら終了

    final value = _tomlStringValue(line, 'modId');
    if (value != null) modId = value;

    final display = _tomlStringValue(line, 'displayName');
    if (display != null) displayName = display;

    final ver = _tomlStringValue(line, 'version');
    if (ver != null) version = ver;
  }

  if (modId == null || modId.isEmpty) return null;

  return ModInfo(
    id: modId,
    name: displayName != null && displayName.isNotEmpty ? displayName : modId,
    version: version != null && version.isNotEmpty ? version : 'unknown',
    source: ModInfoSource.forgeModsToml,
  );
}

/// `key = "value"` 形式の行から [key] に一致する値を取り出す。
String? _tomlStringValue(String line, String key) {
  final pattern = RegExp('^${RegExp.escape(key)}\\s*=\\s*"([^"]*)"');
  final match = pattern.firstMatch(line);
  return match?.group(1);
}

/// `META-INF/MANIFEST.MF`(最終手段)から MOD 情報を作る。
///
/// feature-spec.md §6.1 の通り、MANIFEST.MF しか情報源がない場合は MOD ID を
/// `unknown` とする。この情報源に到達できたということは MOD 自体は存在する
/// ため(スキップにはしない)、常に値を返す。
ModInfo extractModInfoFromManifest(String content) {
  return const ModInfo(
    id: 'unknown',
    name: 'unknown',
    version: 'unknown',
    source: ModInfoSource.manifest,
  );
}

/// `fabric.mod.json` → `mods.toml` → `MANIFEST.MF` の優先順で MOD 情報を解決する。
///
/// いずれの情報源も存在しない(すべて `null`)場合は `null` を返し、
/// 呼び出し側でスキップ扱いにする。
ModInfo? resolveModInfo({
  String? fabricModJson,
  String? modsToml,
  String? manifestMf,
}) {
  if (fabricModJson != null) {
    final info = extractModInfoFromFabricJson(fabricModJson);
    if (info != null) return info;
  }
  if (modsToml != null) {
    final info = extractModInfoFromModsToml(modsToml);
    if (info != null) return info;
  }
  if (manifestMf != null) {
    return extractModInfoFromManifest(manifestMf);
  }
  return null;
}

const _bom = '﻿';

String _stripBom(String text) =>
    text.startsWith(_bom) ? text.substring(1) : text;
