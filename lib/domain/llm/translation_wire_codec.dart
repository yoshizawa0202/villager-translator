import 'dart:convert';

/// 利用者が編集する翻訳方針とは独立して、毎回付加する通信形式の必須指示。
const String kTranslationWireProtocolInstruction = r'''## Required Output Format
- Return exactly one physical line for each input entry, in the same order.
- Keep every key unchanged.
- Output each entry as: key: "translated value"
- The value must be a valid JSON string literal.
- Escape line breaks as \n, carriage returns as \r, tabs as \t, quotes as \", and backslashes as \\.
- Do not add headers, comments, bullets, or code fences.''';

/// 翻訳値をJSON文字列リテラルとして1物理行へ符号化する。
String encodeTranslationValue(String value) => jsonEncode(value);

/// LLMから返された値を復号する。
///
/// 引用符で始まる値はJSON文字列として厳密に復号する。引用符なしの値は、
/// 旧形式 `key: value` との後方互換のためそのまま受理する。
String decodeTranslationValue(String encodedValue) {
  final trimmed = encodedValue.trim();
  if (!trimmed.startsWith('"')) return trimmed;

  dynamic decoded;
  try {
    decoded = jsonDecode(trimmed);
  } on FormatException {
    throw FormatException('翻訳値が正しいJSON文字列ではありません: $trimmed');
  }
  if (decoded is! String) {
    throw FormatException('翻訳値はJSON文字列である必要があります: $trimmed');
  }
  return decoded;
}

/// 翻訳対象を `key: JSON文字列リテラル` の1物理行1エントリへ整形する。
String encodeTranslationContent(Map<String, String> content) => content.entries
    .map((entry) => '${entry.key}: ${encodeTranslationValue(entry.value)}')
    .join('\n');
