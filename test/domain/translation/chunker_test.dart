import 'package:flutter_test/flutter_test.dart';
import 'package:villager_translator/domain/translation/chunker.dart';

void main() {
  group('chunkByEntryCount', () {
    test('チャンクサイズより多いエントリを渡すと固定長分割される(端数チャンクも生成される)', () {
      final entries = {for (var i = 0; i < 5; i++) 'key$i': 'value$i'};

      final chunks = chunkByEntryCount(entries, 2);

      expect(chunks.length, 3);
      expect(chunks[0], {'key0': 'value0', 'key1': 'value1'});
      expect(chunks[1], {'key2': 'value2', 'key3': 'value3'});
      expect(chunks[2], {'key4': 'value4'});
    });

    test('エントリ数がちょうどチャンクサイズの倍数の場合は端数チャンクが生成されない', () {
      final entries = {'a': '1', 'b': '2', 'c': '3', 'd': '4'};

      final chunks = chunkByEntryCount(entries, 2);

      expect(chunks.length, 2);
    });

    test('空の Map を渡すと空のリストを返す', () {
      expect(chunkByEntryCount({}, 3), isEmpty);
    });
  });

  group('chunkByTokenCount', () {
    int charCountEstimator(String text) => text.length;

    test('概算トークン数がしきい値を超えないように貪欲法で分割される', () {
      final entries = {'a': 'x' * 5, 'b': 'x' * 5, 'c': 'x' * 5, 'd': 'x' * 5};

      final chunks = chunkByTokenCount(
        entries,
        maxTokensPerChunk: 10,
        estimateTokens: charCountEstimator,
      );

      expect(chunks.length, 2);
      expect(chunks[0], {'a': 'x' * 5, 'b': 'x' * 5});
      expect(chunks[1], {'c': 'x' * 5, 'd': 'x' * 5});
    });

    test('単一エントリがしきい値を超える場合は文末記号での分割を試みる', () {
      final entries = {'long': 'First sentence. Second sentence! Third?'};

      final chunks = chunkByTokenCount(
        entries,
        maxTokensPerChunk: 10,
        estimateTokens: charCountEstimator,
      );

      expect(chunks, [
        {'long': 'First sentence.'},
        {'long': 'Second sentence!'},
        {'long': 'Third?'},
      ]);
    });

    test('文末記号が無く分割できない場合はそのまま1エントリとして返す', () {
      final entries = {'long': 'x' * 20};

      final chunks = chunkByTokenCount(
        entries,
        maxTokensPerChunk: 10,
        estimateTokens: charCountEstimator,
      );

      expect(chunks, [
        {'long': 'x' * 20},
      ]);
    });

    test('トークン見積り関数が例外を投げた場合、既定でエントリ数ベースへフォールバックする', () {
      final entries = {for (var i = 0; i < 5; i++) 'key$i': 'value$i'};

      final chunks = chunkByTokenCount(
        entries,
        maxTokensPerChunk: 10,
        estimateTokens: (_) => throw Exception('見積り失敗'),
        entryBasedChunkSize: 2,
      );

      expect(chunks.length, 3);
      expect(chunks[0], {'key0': 'value0', 'key1': 'value1'});
      expect(chunks[2], {'key4': 'value4'});
    });

    test('fallbackToEntryBased が false の場合、見積り失敗時は例外がそのまま伝播する', () {
      final entries = {'a': '1'};

      expect(
        () => chunkByTokenCount(
          entries,
          maxTokensPerChunk: 10,
          estimateTokens: (_) => throw Exception('見積り失敗'),
          fallbackToEntryBased: false,
        ),
        throwsException,
      );
    });
  });

  group('splitBySentenceBoundary', () {
    test('文末記号ごとに分割し、前後の空白は除去される', () {
      final result = splitBySentenceBoundary(
        'First sentence. Second sentence! Third?',
      );

      expect(result, ['First sentence.', 'Second sentence!', 'Third?']);
    });

    test('文末記号が含まれない場合は元のテキストをそのまま1件のリストとして返す', () {
      final result = splitBySentenceBoundary('句読点のない文字列');

      expect(result, ['句読点のない文字列']);
    });
  });
}
