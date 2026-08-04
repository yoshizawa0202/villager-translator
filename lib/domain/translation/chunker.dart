/// 翻訳対象エントリのチャンク分割ロジック(feature-spec.md §5.2)。
///
/// 「キー単位」(MOD 向け)・「ファイル/本単位(常に1チャンク)」(クエスト・
/// ガイドブック向け)のいずれの呼び出しパターンにも対応できるよう、本ファイルの
/// 関数は汎用的な `Map<String, String>` に対する分割のみを行う。実際にどちらの
/// 粒度で呼び出すかは各機能仕様(`004`〜`007`)側が選択する
/// (feature-spec.md §16.1)。
library;

/// [entries] を [chunkSize] 件ごとに固定長分割する(エントリ数ベース、既定)。
///
/// 挿入順を維持したまま先頭から詰めていき、端数は最後のチャンクに残す。
List<Map<String, String>> chunkByEntryCount(
  Map<String, String> entries,
  int chunkSize,
) {
  if (chunkSize <= 0) {
    throw ArgumentError.value(chunkSize, 'chunkSize', '1以上を指定してください');
  }

  final chunks = <Map<String, String>>[];
  var current = <String, String>{};

  for (final entry in entries.entries) {
    current[entry.key] = entry.value;
    if (current.length == chunkSize) {
      chunks.add(current);
      current = {};
    }
  }
  if (current.isNotEmpty) {
    chunks.add(current);
  }

  return chunks;
}

/// エントリ1件のテキストから概算トークン数を見積もる関数。
///
/// プロバイダーごとの見積り方法の違いを吸収するため、呼び出し側が注入する。
typedef TokenEstimator = int Function(String text);

/// [entries] を、概算トークン数が [maxTokensPerChunk] を超えないよう貪欲法で
/// 分割する(トークンベース、オプトイン)。
///
/// 単一エントリの見積りトークン数が [maxTokensPerChunk] を超える場合は
/// [splitBySentenceBoundary] による文末分割を試み、分割できた各部分をそれぞれ
/// 単独のチャンクとして返す。分割できない場合はそのまま1エントリのチャンクと
/// して返す(しきい値を超過したままでも送信する)。
///
/// [estimateTokens] が例外を投げた場合、[fallbackToEntryBased] が真
/// (既定 ON)であれば [chunkByEntryCount] へフォールバックする。偽の場合は
/// 例外をそのまま伝播する。
List<Map<String, String>> chunkByTokenCount(
  Map<String, String> entries, {
  required int maxTokensPerChunk,
  required TokenEstimator estimateTokens,
  bool fallbackToEntryBased = true,
  int entryBasedChunkSize = 50,
}) {
  try {
    return _chunkByTokenCountGreedy(entries, maxTokensPerChunk, estimateTokens);
  } catch (_) {
    if (!fallbackToEntryBased) {
      rethrow;
    }
    return chunkByEntryCount(entries, entryBasedChunkSize);
  }
}

List<Map<String, String>> _chunkByTokenCountGreedy(
  Map<String, String> entries,
  int maxTokensPerChunk,
  TokenEstimator estimateTokens,
) {
  final chunks = <Map<String, String>>[];
  var current = <String, String>{};
  var currentTokens = 0;

  void flush() {
    if (current.isNotEmpty) {
      chunks.add(current);
      current = <String, String>{};
      currentTokens = 0;
    }
  }

  for (final entry in entries.entries) {
    final tokens = estimateTokens(entry.value);

    if (tokens > maxTokensPerChunk) {
      flush();
      final parts = splitBySentenceBoundary(entry.value);
      if (parts.length <= 1) {
        chunks.add({entry.key: entry.value});
      } else {
        for (final part in parts) {
          chunks.add({entry.key: part});
        }
      }
      continue;
    }

    if (current.isNotEmpty && currentTokens + tokens > maxTokensPerChunk) {
      flush();
    }
    current[entry.key] = entry.value;
    currentTokens += tokens;
  }
  flush();

  return chunks;
}

/// [text] を文末記号(`.` `!` `?`)で分割する。
///
/// 分割点が見つからない場合は分割を諦め、[text] をそのまま1件のリストとして
/// 返す(feature-spec.md §5.2: 「分割できない場合はそのまま送信する」)。
List<String> splitBySentenceBoundary(String text) {
  final pattern = RegExp(r'[^.!?]*[.!?]+');
  final parts = <String>[];
  var lastEnd = 0;

  for (final match in pattern.allMatches(text)) {
    final part = text.substring(match.start, match.end).trim();
    if (part.isNotEmpty) {
      parts.add(part);
    }
    lastEnd = match.end;
  }

  final remainder = text.substring(lastEnd).trim();
  if (remainder.isNotEmpty) {
    parts.add(remainder);
  }

  if (parts.length <= 1) {
    return [text];
  }
  return parts;
}
