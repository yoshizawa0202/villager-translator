import 'package:flutter_test/flutter_test.dart';
import 'package:villager_translator/domain/common/cancellation_token.dart';
import 'package:villager_translator/domain/customfiletranslation/custom_file_scan_entry.dart';
import 'package:villager_translator/domain/customfiletranslation/custom_file_translation_service.dart';

CustomFileScanEntry _jsonEntry(String path, Map<String, String> sourceEntries) {
  return CustomFileScanEntry(
    format: CustomFileFormat.json,
    absolutePath: '/root/$path',
    relativePath: path,
    sourceEntries: sourceEntries,
    jsonRoot: const {},
  );
}

CustomFileScanEntry _snbtEntry(String path, String content) {
  return CustomFileScanEntry(
    format: CustomFileFormat.snbt,
    absolutePath: '/root/$path',
    relativePath: path,
    sourceEntries: {kCustomSnbtContentKey: content},
  );
}

void main() {
  group('translateCustomFileEntries', () {
    test('選択された全ファイルが、既存翻訳の有無に関わらず常に翻訳対象になる(受け入れ条件2)', () async {
      final entry = _jsonEntry('a.json', {'title': 'Hello'});

      final result = await translateCustomFileEntries(
        selectedEntries: [entry],
        translateChunk: (chunk) async =>
            chunk.map((k, v) => MapEntry(k, '[訳]$v')),
      );

      expect(result.translatedPaths, [entry.relativePath]);
      expect(result.outputs.single.entries, {'title': '[訳]Hello'});
    });

    test('SNBT はファイル全体が1つの翻訳単位として渡される(受け入れ条件6)', () async {
      final entry = _snbtEntry('a.snbt', 'raw content');

      final chunks = <Map<String, String>>[];
      final result = await translateCustomFileEntries(
        selectedEntries: [entry],
        translateChunk: (chunk) async {
          chunks.add(chunk);
          return chunk.map((k, v) => MapEntry(k, '[訳]$v'));
        },
      );

      expect(chunks, [
        {kCustomSnbtContentKey: 'raw content'},
      ]);
      expect(result.outputs.single.entries, {
        kCustomSnbtContentKey: '[訳]raw content',
      });
    });

    test('JSON もファイル全体が1つの翻訳単位として渡され、キー単位に分割されない', () async {
      final entry = _jsonEntry('a.json', {'a': '1', 'b': '2', 'c': '3'});

      final chunkSizes = <int>[];
      var callCount = 0;
      await translateCustomFileEntries(
        selectedEntries: [entry],
        translateChunk: (chunk) async {
          callCount++;
          chunkSizes.add(chunk.length);
          return chunk.map((k, v) => MapEntry(k, '[訳]$v'));
        },
      );

      expect(callCount, 1);
      expect(chunkSizes, [3]);
    });

    test('翻訳対象が0件のファイルはスキップされる', () async {
      final entry = _jsonEntry('empty.json', {});

      final result = await translateCustomFileEntries(
        selectedEntries: [entry],
        translateChunk: (chunk) async => chunk,
      );

      expect(result.skippedPaths, [entry.relativePath]);
      expect(result.outputs, isEmpty);
    });

    test('処理順序は相対パスの昇順に決定論的に固定される', () async {
      final entries = [
        _jsonEntry('z.json', {'k': 'v'}),
        _jsonEntry('a.json', {'k': 'v'}),
      ];

      final result = await translateCustomFileEntries(
        selectedEntries: entries,
        translateChunk: (chunk) async => chunk,
      );

      expect(result.translatedPaths, ['a.json', 'z.json']);
    });

    test('キャンセル済みの場合、現在のファイルは完了させた上で以降のファイルは処理しない(受け入れ条件5)', () async {
      final token = CancellationToken();
      final entryA = _jsonEntry('a.json', {'a': '1'});
      final entryB = _jsonEntry('b.json', {'a': '1'});

      final result = await translateCustomFileEntries(
        selectedEntries: [entryA, entryB],
        translateChunk: (chunk) async {
          token.cancel();
          return chunk.map((k, v) => MapEntry(k, '[訳]$v'));
        },
        cancellationToken: token,
      );

      expect(result.translatedPaths, ['a.json']);
    });

    test('進捗コールバックが対象1件ごとに完了件数/総件数を通知する', () async {
      final entryA = _jsonEntry('a.json', {'a': '1'});
      final entryB = _jsonEntry('b.json', {'a': '1'});
      final overallUpdates = <List<int>>[];

      await translateCustomFileEntries(
        selectedEntries: [entryA, entryB],
        translateChunk: (chunk) async =>
            chunk.map((k, v) => MapEntry(k, '[訳]$v')),
        onOverallProgress: (progress) =>
            overallUpdates.add([progress.completedItems, progress.totalItems]),
      );

      expect(overallUpdates, [
        [1, 2],
        [2, 2],
      ]);
    });

    test('onChunkResult がファイルの相対パス付きで結果を通知する(Issue#10)', () async {
      final entry = _jsonEntry('a.json', {'a': '1'});
      final labels = <String>[];

      await translateCustomFileEntries(
        selectedEntries: [entry],
        translateChunk: (chunk) async =>
            chunk.map((k, v) => MapEntry(k, '[訳]$v')),
        onChunkResult: (itemLabel, result) => labels.add(itemLabel),
      );

      expect(labels, ['a.json']);
    });
  });
}
