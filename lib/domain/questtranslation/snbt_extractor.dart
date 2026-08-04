/// SNBT(FTB Quests のクエストファイル)からの翻訳対象文字列抽出・再構成
/// (feature-spec.md §7.1、§7.3)。
///
/// SNBT の内容種別(`json_keys` / `direct_text`)判定ロジックは実装せず、
/// `title` `subtitle` `description` の正規表現抽出のみで完結させる
/// (`005-quest-translation.md` の移行上の判断)。
library;

/// 抽出した1つの引用符文字列の、元テキスト中の位置(内容部分、引用符自体は含まない)。
class SnbtStringSpan {
  const SnbtStringSpan({
    required this.start,
    required this.end,
    required this.rawValue,
  });

  /// 内容の開始インデックス(開き引用符の直後)。
  final int start;

  /// 内容の終了インデックス(閉じ引用符の直前、exclusive)。
  final int end;

  /// 引用符間の生の内容(エスケープシーケンスを含む、未デコード)。
  final String rawValue;
}

final _keyPattern = RegExp(r'\b(?:title|subtitle|description)\s*:\s*');

/// [content] から `title` `subtitle` `description` の値を抽出する。
///
/// 各キーの直後が `"..."`(単一文字列)の場合はその1件を、`[...]`(文字列の
/// 配列。FTB Quests の複数行 description で使われる)の場合は配列内の各
/// 引用符文字列をそれぞれ抽出する。エスケープされた `"`(前方の連続する `\`
/// の数が奇数)は終端とみなさない(feature-spec.md §7.1、受け入れ条件4)。
List<SnbtStringSpan> extractSnbtTranslatableSpans(String content) {
  final spans = <SnbtStringSpan>[];

  for (final match in _keyPattern.allMatches(content)) {
    var pos = _skipWhitespace(content, match.end);
    if (pos >= content.length) continue;

    if (content[pos] == '"') {
      final span = _readQuotedString(content, pos);
      if (span != null) spans.add(span);
      continue;
    }

    if (content[pos] == '[') {
      pos++;
      while (pos < content.length) {
        pos = _skipWhitespaceAndCommas(content, pos);
        if (pos >= content.length || content[pos] == ']') break;
        if (content[pos] != '"') break;
        final span = _readQuotedString(content, pos);
        if (span == null) break;
        spans.add(span);
        pos = span.end + 1;
      }
    }
  }

  return spans;
}

int _skipWhitespace(String content, int pos) {
  while (pos < content.length && _isSnbtWhitespace(content[pos])) {
    pos++;
  }
  return pos;
}

int _skipWhitespaceAndCommas(String content, int pos) {
  while (pos < content.length &&
      (_isSnbtWhitespace(content[pos]) || content[pos] == ',')) {
    pos++;
  }
  return pos;
}

bool _isSnbtWhitespace(String char) =>
    char == ' ' || char == '\t' || char == '\n' || char == '\r';

/// [content] の [quoteStart](`"` の位置)から、エスケープされていない閉じ
/// 引用符までを読み取る。閉じ引用符が見つからない場合は `null` を返す。
SnbtStringSpan? _readQuotedString(String content, int quoteStart) {
  var i = quoteStart + 1;
  while (i < content.length) {
    if (content[i] == '"' && !_isEscaped(content, i)) {
      return SnbtStringSpan(
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
/// されているかどうかを判定する(feature-spec.md §7.1)。
bool _isEscaped(String content, int pos) {
  var backslashes = 0;
  var j = pos - 1;
  while (j >= 0 && content[j] == '\\') {
    backslashes++;
    j--;
  }
  return backslashes.isOdd;
}

/// SNBT のエスケープシーケンス(`\"` `\\`)をデコードする。
String decodeSnbtEscapes(String raw) {
  final buffer = StringBuffer();
  for (var i = 0; i < raw.length; i++) {
    if (raw[i] == '\\' &&
        i + 1 < raw.length &&
        (raw[i + 1] == '"' || raw[i + 1] == '\\')) {
      buffer.write(raw[i + 1]);
      i++;
    } else {
      buffer.write(raw[i]);
    }
  }
  return buffer.toString();
}

/// SNBT のエスケープシーケンス(`\"` `\\`)へエンコードする([decodeSnbtEscapes] の逆)。
String encodeSnbtEscapes(String raw) {
  final buffer = StringBuffer();
  for (final rune in raw.runes) {
    if (rune == 0x22) {
      buffer.write(r'\"');
    } else if (rune == 0x5c) {
      buffer.write(r'\\');
    } else {
      buffer.writeCharCode(rune);
    }
  }
  return buffer.toString();
}

/// SNBT ファイル1件から抽出した翻訳単位。
///
/// [entries] のキーは抽出順の連番文字列(`"0"` `"1"` ...)で、[spans] と
/// 同じ並び順に対応する(feature-spec.md §7.3: ファイル全体を1つの翻訳単位とする)。
class SnbtTranslationUnit {
  const SnbtTranslationUnit({
    required this.originalContent,
    required this.entries,
    required this.spans,
  });

  final String originalContent;
  final Map<String, String> entries;
  final List<SnbtStringSpan> spans;
}

/// [content] から翻訳単位を構築する。`title`/`subtitle`/`description` が
/// 1件も見つからない場合、[SnbtTranslationUnit.entries] は空になる。
SnbtTranslationUnit buildSnbtTranslationUnit(String content) {
  final spans = extractSnbtTranslatableSpans(content);
  final entries = <String, String>{
    for (var i = 0; i < spans.length; i++)
      '$i': decodeSnbtEscapes(spans[i].rawValue),
  };
  return SnbtTranslationUnit(
    originalContent: content,
    entries: entries,
    spans: spans,
  );
}

/// [originalContent] 中の [spans] を [translatedEntries](キーは抽出順の連番
/// 文字列)の値で置き換えた全文を再構成する。対応する翻訳結果がないスパンは
/// 元の内容のまま残す(部分成功時のフォールバック)。
///
/// 同じファイルへ直接上書きする(言語サフィックス付きの別ファイルは作らない、
/// 受け入れ条件5)。
String reconstructSnbt(
  String originalContent,
  List<SnbtStringSpan> spans,
  Map<String, String> translatedEntries,
) {
  final buffer = StringBuffer();
  var cursor = 0;

  for (var i = 0; i < spans.length; i++) {
    final span = spans[i];
    final translated = translatedEntries['$i'];
    buffer.write(originalContent.substring(cursor, span.start));
    buffer.write(
      translated != null ? encodeSnbtEscapes(translated) : span.rawValue,
    );
    cursor = span.end;
  }
  buffer.write(originalContent.substring(cursor));

  return buffer.toString();
}
