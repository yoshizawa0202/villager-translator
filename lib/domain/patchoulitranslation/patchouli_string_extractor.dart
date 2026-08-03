/// Patchouli ガイドブック JSON からの翻訳対象文字列抽出・再構成
/// (feature-spec.md §8.1、§8.2)。
///
/// JSON 全体を構造的にパースせず、`"name"` `"description"` `"title"` `"text"`
/// という**引用符付きキー**の直後の文字列値のみを正規表現で抽出する軽量な方式
/// (`docs/specs/006-patchouli-translation.md`)。キーが必ず `"` で囲まれる
/// ことを利用し、`SnbtStringSpan`(`snbt_extractor.dart`)の JSON 版として、
/// `icon`/`category`/`pages` 配列の型情報などそれ以外のキーは一切対象にしない。
library;

import 'dart:convert';

/// 抽出した1つの引用符文字列値の、元テキスト中の位置(内容部分、引用符自体は含まない)。
class PatchouliStringSpan {
  const PatchouliStringSpan({
    required this.start,
    required this.end,
    required this.rawValue,
  });

  /// 内容の開始インデックス(開き引用符の直後)。
  final int start;

  /// 内容の終了インデックス(閉じ引用符の直前、exclusive)。
  final int end;

  /// 引用符間の生の内容(JSON エスケープシーケンスを含む、未デコード)。
  final String rawValue;
}

final _keyPattern = RegExp(r'"(?:name|description|title|text)"\s*:\s*"');

/// [content] から `"name"` `"description"` `"title"` `"text"` の文字列値を
/// 抽出する(feature-spec.md §8.1、受け入れ条件3)。
///
/// 値が文字列でない場合(数値・真偽値・オブジェクト・配列)はキーが一致しても
/// 対象にしない。エスケープされた `"`(前方の連続する `\` の数が奇数)は
/// 終端とみなさない。
List<PatchouliStringSpan> extractPatchouliTranslatableSpans(String content) {
  final spans = <PatchouliStringSpan>[];

  for (final match in _keyPattern.allMatches(content)) {
    final quoteStart = match.end - 1;
    final span = _readQuotedString(content, quoteStart);
    if (span != null) spans.add(span);
  }

  return spans;
}

/// [content] の [quoteStart](`"` の位置)から、エスケープされていない閉じ
/// 引用符までを読み取る。閉じ引用符が見つからない場合は `null` を返す。
PatchouliStringSpan? _readQuotedString(String content, int quoteStart) {
  var i = quoteStart + 1;
  while (i < content.length) {
    if (content[i] == '"' && !_isEscaped(content, i)) {
      return PatchouliStringSpan(
        start: quoteStart + 1,
        end: i,
        rawValue: content.substring(quoteStart + 1, i),
      );
    }
    i++;
  }
  return null;
}

/// [pos] の文字が、直前の連続する `\` の数が奇数であることによりエスケープ
/// されているかどうかを判定する。
bool _isEscaped(String content, int pos) {
  var backslashes = 0;
  var j = pos - 1;
  while (j >= 0 && content[j] == '\\') {
    backslashes++;
    j--;
  }
  return backslashes.isOdd;
}

/// JSON 文字列のエスケープシーケンス(`\"` `\\` `\n` `\uXXXX` 等)をデコードする。
///
/// 単一の文字列リテラルとして [dart:convert] の `jsonDecode` に委譲することで、
/// サロゲートペアを含む `\uXXXX` などの正確なデコードを保証する。
String decodePatchouliJsonEscapes(String raw) => jsonDecode('"$raw"') as String;

/// JSON 文字列のエスケープシーケンスへエンコードする([decodePatchouliJsonEscapes] の逆)。
///
/// [jsonEncode] は常に前後を `"` で囲んだ文字列リテラルを返すため、それを
/// 除去して内容のみを返す。
String encodePatchouliJsonEscapes(String value) {
  final encoded = jsonEncode(value);
  return encoded.substring(1, encoded.length - 1);
}

/// Patchouli ガイドブック内の1ファイル分の翻訳単位。
///
/// [entries] のキーは抽出順の連番文字列(`"0"` `"1"` ...)で、[spans] と
/// 同じ並び順に対応する(feature-spec.md §8.1: ファイル単体の抽出結果。
/// 複数ファイルの統合は呼び出し側の責務)。
class PatchouliFileTranslationUnit {
  const PatchouliFileTranslationUnit({
    required this.originalContent,
    required this.entries,
    required this.spans,
  });

  final String originalContent;
  final Map<String, String> entries;
  final List<PatchouliStringSpan> spans;
}

/// [content] から翻訳単位を構築する。対象キーが1件も見つからない場合、
/// [PatchouliFileTranslationUnit.entries] は空になる。
PatchouliFileTranslationUnit buildPatchouliFileTranslationUnit(String content) {
  final spans = extractPatchouliTranslatableSpans(content);
  final entries = <String, String>{
    for (var i = 0; i < spans.length; i++)
      '$i': decodePatchouliJsonEscapes(spans[i].rawValue),
  };
  return PatchouliFileTranslationUnit(
    originalContent: content,
    entries: entries,
    spans: spans,
  );
}

/// [originalContent] 中の [spans] を [translatedEntries](キーは抽出順の連番
/// 文字列)の値で置き換えた全文を再構成する。対応する翻訳結果がないスパンは
/// 元の内容のまま残す(部分成功時のフォールバック)。
///
/// `icon`/`category`/`pages` の型情報など、対象キー以外の内容は一切変更しない
/// (フルコピー方式、feature-spec.md §8.2、受け入れ条件7)。
String reconstructPatchouliFile(
  String originalContent,
  List<PatchouliStringSpan> spans,
  Map<String, String> translatedEntries,
) {
  final buffer = StringBuffer();
  var cursor = 0;

  for (var i = 0; i < spans.length; i++) {
    final span = spans[i];
    final translated = translatedEntries['$i'];
    buffer.write(originalContent.substring(cursor, span.start));
    buffer.write(
      translated != null
          ? encodePatchouliJsonEscapes(translated)
          : span.rawValue,
    );
    cursor = span.end;
  }
  buffer.write(originalContent.substring(cursor));

  return buffer.toString();
}
