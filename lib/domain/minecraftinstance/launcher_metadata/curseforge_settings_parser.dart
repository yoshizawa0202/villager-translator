import 'dart:convert';

/// CurseForge の設定から Minecraft Modding Folder を取得する際に探すキー名
/// (011-launcher-instance-discovery.md §7、「要検証項目」)。
///
/// 設定ファイル名およびキー名は公式資料で確定できていないため、実際の
/// CurseForge が使い得る候補を順に探す。1つも見つからなければ標準パスへ
/// フォールバックする(AC-03)。
const List<String> kCurseForgeModdingFolderKeys = [
  'gameInstancePath',
  'moddingFolder',
  'installDirectory',
  'installPath',
  'instancePath',
];

/// CurseForge の設定 JSON から Modding Folder のパスを取り出す(§7)。
///
/// 設定の入れ子構造も揺れ得るため、JSON 全体を再帰的にたどり
/// [kCurseForgeModdingFolderKeys] のいずれかに一致する文字列値を探す。
/// 不正 JSON・該当キー無しでは例外を投げず `null` を返す。
String? parseCurseForgeModdingFolder(String content) {
  final Object? decoded;
  try {
    decoded = jsonDecode(content);
  } catch (_) {
    return null;
  }
  return _findModdingFolder(decoded);
}

String? _findModdingFolder(Object? node) {
  if (node is Map) {
    for (final key in kCurseForgeModdingFolderKeys) {
      final value = node[key];
      if (value is String && value.trim().isNotEmpty) return value.trim();
    }
    for (final value in node.values) {
      final found = _findModdingFolder(value);
      if (found != null) return found;
    }
    return null;
  }
  if (node is List) {
    for (final value in node) {
      final found = _findModdingFolder(value);
      if (found != null) return found;
    }
  }
  return null;
}
