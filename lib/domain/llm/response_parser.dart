/// LLM 応答テキストから `key: value` 形式の行を抽出し、翻訳結果の Map を復元する。
///
/// まず各キーに対する厳密な正規表現一致(`_parseStrict`)を試みる。全キーを
/// 復元できなかった場合は、Markdown 装飾(コードブロック記号・見出し・箇条書き
/// 記号等)やヘッダー行を除去した上で行位置ベースの対応付け(`_parseByLinePosition`)
/// にフォールバックする(feature-spec.md §5.3)。
/// いずれの方法でも元のキー数と一致する結果が得られない場合は
/// [FormatException] を投げる(feature-spec.md §5.3: キー数不一致はエラー扱い)。
Map<String, String> parseTranslationResponse(
  String rawText,
  List<String> originalKeys,
) {
  final strict = _parseStrict(rawText, originalKeys);
  if (strict.length == originalKeys.length) {
    return strict;
  }

  final byPosition = _parseByLinePosition(rawText, originalKeys);
  if (byPosition.length == originalKeys.length) {
    return byPosition;
  }

  throw FormatException(
    '翻訳結果のキー数が一致しません。期待: ${originalKeys.length}件、'
    '復元できた件数: ${byPosition.length}件',
  );
}

Map<String, String> _parseStrict(String rawText, List<String> originalKeys) {
  final lines = rawText.split('\n');
  final result = <String, String>{};

  for (final key in originalKeys) {
    final pattern = RegExp('^${RegExp.escape(key)}:\\s*(.+)\$');
    for (final line in lines) {
      final match = pattern.firstMatch(line.trim());
      if (match != null) {
        result[key] = match.group(1)!.trim();
        break;
      }
    }
  }

  return result;
}

/// Markdown 装飾・ヘッダー行とみなして読み飛ばす行かどうかを判定する。
bool _isNoiseLine(String line) {
  final trimmed = line.trim();
  if (trimmed.isEmpty) return true;
  if (trimmed.startsWith('```')) return true;
  if (trimmed.startsWith('#')) return true;
  if (RegExp(r'^[*\-]\s').hasMatch(trimmed)) return true;

  const noiseKeywords = ['translation', 'here', 'translated'];
  final lower = trimmed.toLowerCase();
  return noiseKeywords.any(lower.contains);
}

/// Markdown 装飾・ヘッダー行を除去した残りの行を、元のキーの並び順に
/// 位置ベースで対応付ける。行数がキー数と一致しない場合は空の Map を返す。
Map<String, String> _parseByLinePosition(
  String rawText,
  List<String> originalKeys,
) {
  final candidateLines = rawText
      .split('\n')
      .where((line) => !_isNoiseLine(line))
      .map((line) => line.trim())
      .toList();

  if (candidateLines.length != originalKeys.length) {
    return {};
  }

  final result = <String, String>{};
  for (var i = 0; i < originalKeys.length; i++) {
    final key = originalKeys[i];
    final line = candidateLines[i];
    final pattern = RegExp('^${RegExp.escape(key)}:\\s*(.+)\$');
    final match = pattern.firstMatch(line);
    result[key] = match != null ? match.group(1)!.trim() : line;
  }
  return result;
}
