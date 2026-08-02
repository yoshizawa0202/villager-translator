/// LLM 応答テキストから `key: value` 形式の行を抽出し、翻訳結果の Map を復元する。
///
/// 本パーサーは各キーに対する厳密な正規表現一致のみを行う最小実装であり、
/// Markdown 装飾の除去や行位置ベースのフォールバックといった高度な検証・
/// リトライロジックは `docs/specs/003-translation-engine.md` の範囲とする。
/// 全キーを復元できない場合は [FormatException] を投げる
/// (feature-spec.md §5.3: キー数不一致はエラー扱い)。
Map<String, String> parseTranslationResponse(
  String rawText,
  List<String> originalKeys,
) {
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

  if (result.length != originalKeys.length) {
    throw FormatException(
      '翻訳結果のキー数が一致しません。期待: ${originalKeys.length}件、'
      '復元できた件数: ${result.length}件',
    );
  }

  return result;
}
