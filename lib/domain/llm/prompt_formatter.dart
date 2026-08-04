/// ユーザープロンプトテンプレートのプレースホルダーを置換する。
///
/// サポートするプレースホルダーは単一波括弧の `{language}` `{line_count}` `{content}`
/// のみ(feature-spec.md §4.3)。`content` は `key: value` 形式で1行1エントリに
/// 整形し、`Map` の反復順(挿入順)をそのまま維持する。
String formatUserPrompt(
  String template, {
  required Map<String, String> content,
  required String targetLanguage,
}) {
  final lines = content.entries.map((e) => '${e.key}: ${e.value}');
  final formattedContent = lines.join('\n');

  return template
      .replaceAll('{language}', targetLanguage)
      .replaceAll('{line_count}', content.length.toString())
      .replaceAll('{content}', formattedContent);
}
