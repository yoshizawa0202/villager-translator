import 'translation_wire_codec.dart';

/// ユーザープロンプトテンプレートのプレースホルダーを置換する。
///
/// サポートするプレースホルダーは単一波括弧の `{language}` `{line_count}` `{content}`
/// のみ(feature-spec.md §4.3)。`content` は値をJSON文字列リテラルへ符号化した
/// 1物理行1エントリに整形し、`Map` の反復順(挿入順)をそのまま維持する。
/// 通信形式の必須指示は編集可能なテンプレートとは独立して末尾へ付加する。
String formatUserPrompt(
  String template, {
  required Map<String, String> content,
  required String targetLanguage,
}) {
  final formattedContent = encodeTranslationContent(content);

  final formatted = template
      .replaceAll('{language}', targetLanguage)
      .replaceAll('{line_count}', content.length.toString())
      .replaceAll('{content}', formattedContent);

  return '${formatted.trimRight()}\n\n$kTranslationWireProtocolInstruction';
}
