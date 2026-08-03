import 'dart:convert';

/// lang ファイルのフォーマット(feature-spec.md §6.1)。
enum LangFormat {
  json,
  lang;

  /// 出力ファイルの拡張子。
  String get extension => this == LangFormat.json ? 'json' : 'lang';
}

const _bom = '﻿';

/// BOM・制御文字(タブ・改行・復帰を除く)を除去する。
///
/// `_comment` キーの除去や BOM・制御文字の除去はパース前に行う
/// (feature-spec.md §6.1、受け入れ条件4)。
String _sanitize(String raw) {
  final withoutBom = raw.startsWith(_bom) ? raw.substring(1) : raw;
  final buffer = StringBuffer();
  for (final rune in withoutBom.runes) {
    final isControl =
        rune < 0x20 && rune != 0x09 && rune != 0x0A && rune != 0x0D;
    if (!isControl) {
      buffer.writeCharCode(rune);
    }
  }
  return buffer.toString();
}

/// JSON 形式の lang ファイルをパースする。`_comment` キーは除外する。
///
/// 破損した JSON は [FormatException] を投げる(呼び出し側が MOD 単位で
/// スキップする、feature-spec.md §6.1 受け入れ条件5)。
Map<String, String> decodeLangJson(String raw) {
  final sanitized = _sanitize(raw);
  final decoded = jsonDecode(sanitized);
  if (decoded is! Map<String, dynamic>) {
    throw const FormatException('lang JSON はオブジェクトである必要があります');
  }

  final result = <String, String>{};
  for (final entry in decoded.entries) {
    if (entry.key == '_comment') continue;
    final value = entry.value;
    if (value is String) {
      result[entry.key] = value;
    }
  }
  return result;
}

/// [entries] をキーでソートして JSON 形式にエンコードする(受け入れ条件13)。
String encodeLangJson(Map<String, String> entries) {
  final sortedKeys = entries.keys.toList()..sort();
  final ordered = {for (final key in sortedKeys) key: entries[key]};
  return const JsonEncoder.withIndent('  ').convert(ordered);
}

/// `.lang` 形式(`key=value` 1行1エントリ)をパースする。
///
/// `#` で始まる行はコメントとして無視し、`_comment` キーも除外する
/// (feature-spec.md §6.1、受け入れ条件4)。
Map<String, String> decodeLangFile(String raw) {
  final sanitized = _sanitize(raw);
  final result = <String, String>{};

  for (final rawLine in sanitized.split('\n')) {
    final line = rawLine.trim().replaceAll('\r', '');
    if (line.isEmpty || line.startsWith('#')) continue;

    final separatorIndex = line.indexOf('=');
    if (separatorIndex < 0) continue;

    final key = line.substring(0, separatorIndex).trim();
    if (key.isEmpty || key == '_comment') continue;

    final value = line.substring(separatorIndex + 1);
    result[key] = value;
  }

  return result;
}

/// [entries] をキーでソートして `.lang` 形式にエンコードする(受け入れ条件13)。
String encodeLangFile(Map<String, String> entries) {
  final sortedKeys = entries.keys.toList()..sort();
  return sortedKeys.map((key) => '$key=${entries[key]}').join('\n');
}

/// [format] に応じてパースを振り分ける。
Map<String, String> decodeLang(String raw, LangFormat format) {
  return format == LangFormat.json ? decodeLangJson(raw) : decodeLangFile(raw);
}

/// [format] に応じてエンコードを振り分ける。
String encodeLang(Map<String, String> entries, LangFormat format) {
  return format == LangFormat.json
      ? encodeLangJson(entries)
      : encodeLangFile(entries);
}
