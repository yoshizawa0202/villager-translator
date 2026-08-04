/// JSON のネスト構造を、文字列の葉ノードのみを対象にドット/ブラケット記法の
/// キー(例 `a.b[2].c`)へフラット化する/差し戻すロジック(feature-spec.md §9)。
library;

/// `jsonDecode` の結果である [root] を走査し、文字列の葉ノードのみを
/// `a.b[2].c` 形式のキーへフラット化する(受け入れ条件3、4)。
///
/// 数値・真偽値・null 等の非文字列の葉は対象に含まれない。
Map<String, String> flattenJsonStrings(dynamic root) {
  final result = <String, String>{};
  _flatten(root, '', result);
  return result;
}

void _flatten(dynamic node, String path, Map<String, String> out) {
  if (node is Map) {
    for (final entry in node.entries) {
      final key = entry.key as String;
      final childPath = path.isEmpty ? key : '$path.$key';
      _flatten(entry.value, childPath, out);
    }
  } else if (node is List) {
    for (var i = 0; i < node.length; i++) {
      _flatten(node[i], '$path[$i]', out);
    }
  } else if (node is String) {
    out[path] = node;
  }
}

/// [root] の構造・型・キー順序を保ったまま、[translated] にある文字列の葉
/// ノードのみを翻訳結果へ差し替えた新しい構造を返す(受け入れ条件5)。
///
/// [translated] に対応する値がない文字列(部分成功時の未翻訳分)は元の値の
/// まま残す。
dynamic rebuildJsonWithTranslations(
  dynamic root,
  Map<String, String> translated,
) {
  return _rebuild(root, '', translated);
}

dynamic _rebuild(dynamic node, String path, Map<String, String> translated) {
  if (node is Map) {
    final result = <String, dynamic>{};
    for (final entry in node.entries) {
      final key = entry.key as String;
      final childPath = path.isEmpty ? key : '$path.$key';
      result[key] = _rebuild(entry.value, childPath, translated);
    }
    return result;
  } else if (node is List) {
    return [
      for (var i = 0; i < node.length; i++)
        _rebuild(node[i], '$path[$i]', translated),
    ];
  } else if (node is String) {
    return translated[path] ?? node;
  }
  return node;
}
