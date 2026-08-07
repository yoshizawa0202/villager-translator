import 'package:flutter_test/flutter_test.dart';
import 'package:villager_translator/domain/common/cancellation_token.dart';
import 'package:villager_translator/domain/patchoulitranslation/patchouli_book_entry.dart';
import 'package:villager_translator/domain/patchoulitranslation/patchouli_translation_service.dart';
import 'package:villager_translator/domain/settings/existing_translation_policy.dart';

PatchouliBookEntry _entry(
  String modId,
  String bookId,
  Map<String, String> sourceEntries, {
  bool hasExistingTranslation = false,
}) {
  return PatchouliBookEntry(
    modId: modId,
    bookId: bookId,
    jarRelativePath: '$modId.jar',
    files: const [],
    sourceEntries: sourceEntries,
    hasExistingTranslation: hasExistingTranslation,
  );
}

Future<Map<String, String>> _fakeTranslate(Map<String, String> chunk) async {
  return chunk.map((key, value) => MapEntry(key, '[訳]$value'));
}

void main() {
  group('translatePatchouliBooks', () {
    test('スキップ方針: 全ミラーファイルが揃っている本はスキップされる(受け入れ条件5)', () async {
      final entry = _entry('modb', 'guide', {'book.json#0': '1'});

      final result = await translatePatchouliBooks(
        selectedEntries: [entry],
        policy: ExistingTranslationPolicy.skip,
        loadExistingTargetEntries: (_) async =>
            const PatchouliExistingTranslation(
              isComplete: true,
              entries: {'book.json#0': '既存'},
            ),
        translateChunk: _fakeTranslate,
      );

      expect(result.skippedBookKeys, ['modb:guide']);
      expect(result.outputs, isEmpty);
    });

    test('スキップ方針: 一部のミラーしかない本はスキップされず翻訳される', () async {
      final entry = _entry('modb', 'guide', {'book.json#0': '1'});

      final result = await translatePatchouliBooks(
        selectedEntries: [entry],
        policy: ExistingTranslationPolicy.skip,
        loadExistingTargetEntries: (_) async =>
            const PatchouliExistingTranslation(isComplete: false, entries: {}),
        translateChunk: _fakeTranslate,
      );

      expect(result.translatedBookKeys, ['modb:guide']);
      expect(result.outputs.single.entries, {'book.json#0': '[訳]1'});
    });

    test('差分更新方針: 複合キー単位で不足分のみ翻訳され、既存エントリの値は変更されない(受け入れ条件6)', () async {
      final entry = _entry('modc', 'guide', {
        'book.json#0': '1',
        'entries/a.json#0': '2',
      });

      final result = await translatePatchouliBooks(
        selectedEntries: [entry],
        policy: ExistingTranslationPolicy.diffUpdate,
        loadExistingTargetEntries: (_) async =>
            const PatchouliExistingTranslation(
              isComplete: false,
              entries: {'book.json#0': '手動修正済み'},
            ),
        translateChunk: _fakeTranslate,
      );

      expect(result.translatedBookKeys, ['modc:guide']);
      expect(result.outputs.single.entries, {
        'book.json#0': '手動修正済み',
        'entries/a.json#0': '[訳]2',
      });
    });

    test('差分更新方針: 不足エントリが1件もない場合はスキップ扱いになる', () async {
      final entry = _entry('modd', 'guide', {'book.json#0': '1'});

      final result = await translatePatchouliBooks(
        selectedEntries: [entry],
        policy: ExistingTranslationPolicy.diffUpdate,
        loadExistingTargetEntries: (_) async =>
            const PatchouliExistingTranslation(
              isComplete: false,
              entries: {'book.json#0': '既存訳'},
            ),
        translateChunk: _fakeTranslate,
      );

      expect(result.skippedBookKeys, ['modd:guide']);
      expect(result.outputs, isEmpty);
    });

    test('全て再翻訳方針: 既存の有無に関わらず全エントリが翻訳され、既存確認は行われない(受け入れ条件10 相当)', () async {
      final entry = _entry('mode', 'guide', {
        'book.json#0': '1',
        'entries/a.json#0': '2',
      });

      var loaderCalled = false;
      final result = await translatePatchouliBooks(
        selectedEntries: [entry],
        policy: ExistingTranslationPolicy.retranslateAll,
        loadExistingTargetEntries: (_) async {
          loaderCalled = true;
          return const PatchouliExistingTranslation(
            isComplete: true,
            entries: {},
          );
        },
        translateChunk: _fakeTranslate,
      );

      expect(loaderCalled, isFalse);
      expect(result.translatedBookKeys, ['mode:guide']);
      expect(result.outputs.single.entries, {
        'book.json#0': '[訳]1',
        'entries/a.json#0': '[訳]2',
      });
    });

    test('本全体が1つの翻訳単位として渡され、キー単位に分割されない(受け入れ条件4)', () async {
      final entry = _entry('modf', 'guide', {
        'book.json#0': '1',
        'entries/a.json#0': '2',
        'entries/a.json#1': '3',
      });

      var callCount = 0;
      final chunkSizes = <int>[];
      await translatePatchouliBooks(
        selectedEntries: [entry],
        policy: ExistingTranslationPolicy.retranslateAll,
        loadExistingTargetEntries: (_) async =>
            const PatchouliExistingTranslation(isComplete: false, entries: {}),
        translateChunk: (chunk) async {
          callCount++;
          chunkSizes.add(chunk.length);
          return chunk.map((k, v) => MapEntry(k, '[訳]$v'));
        },
      );

      expect(callCount, 1);
      expect(chunkSizes, [3]);
    });

    test('抽出対象が0件の本はスキップされる', () async {
      final entry = _entry('modg', 'empty', {});

      final result = await translatePatchouliBooks(
        selectedEntries: [entry],
        policy: ExistingTranslationPolicy.retranslateAll,
        loadExistingTargetEntries: (_) async =>
            const PatchouliExistingTranslation(isComplete: false, entries: {}),
        translateChunk: _fakeTranslate,
      );

      expect(result.skippedBookKeys, ['modg:empty']);
      expect(result.outputs, isEmpty);
    });

    test('modId:bookId のアルファベット順に処理される', () async {
      final processedOrder = <String>[];
      final entryZ = _entry('zmod', 'guide', {'book.json#0': '1'});
      final entryA = _entry('amod', 'guide', {'book.json#0': '1'});

      final result = await translatePatchouliBooks(
        selectedEntries: [entryZ, entryA],
        policy: ExistingTranslationPolicy.diffUpdate,
        loadExistingTargetEntries: (entry) async {
          processedOrder.add(entry.bookKey);
          return const PatchouliExistingTranslation(
            isComplete: false,
            entries: {},
          );
        },
        translateChunk: _fakeTranslate,
      );

      expect(processedOrder, ['amod:guide', 'zmod:guide']);
      expect(result.translatedBookKeys, ['amod:guide', 'zmod:guide']);
    });

    test('キャンセル済みの場合、現在の本は完了させた上で以降の本は処理しない(受け入れ条件5)', () async {
      final token = CancellationToken();
      final entryA = _entry('amod', 'guide', {'book.json#0': '1'});
      final entryB = _entry('bmod', 'guide', {'book.json#0': '1'});

      final result = await translatePatchouliBooks(
        selectedEntries: [entryA, entryB],
        policy: ExistingTranslationPolicy.retranslateAll,
        loadExistingTargetEntries: (_) async =>
            const PatchouliExistingTranslation(isComplete: false, entries: {}),
        translateChunk: (chunk) async {
          // entryA のチャンク翻訳が完了する直前にキャンセルする
          // (「実行中のチャンクは中断しない」ことを確認するため)。
          token.cancel();
          return chunk.map((k, v) => MapEntry(k, '[訳]$v'));
        },
        cancellationToken: token,
      );

      expect(result.translatedBookKeys, ['amod:guide']);
    });

    test('進捗コールバックが対象1件ごとに完了件数/総件数を通知する', () async {
      final entryA = _entry('amod', 'guide', {'book.json#0': '1'});
      final entryB = _entry('bmod', 'guide', {'book.json#0': '1'});
      final overallUpdates = <List<int>>[];

      await translatePatchouliBooks(
        selectedEntries: [entryA, entryB],
        policy: ExistingTranslationPolicy.retranslateAll,
        loadExistingTargetEntries: (_) async =>
            const PatchouliExistingTranslation(isComplete: false, entries: {}),
        translateChunk: _fakeTranslate,
        onOverallProgress: (progress) =>
            overallUpdates.add([progress.completedItems, progress.totalItems]),
      );

      expect(overallUpdates, [
        [1, 2],
        [2, 2],
      ]);
    });

    test('onChunkResult が本のキー(modId:bookId)付きで結果を通知する(Issue#10)', () async {
      final entry = _entry('amod', 'guide', {'book.json#0': '1'});
      final labels = <String>[];

      await translatePatchouliBooks(
        selectedEntries: [entry],
        policy: ExistingTranslationPolicy.retranslateAll,
        loadExistingTargetEntries: (_) async =>
            const PatchouliExistingTranslation(isComplete: false, entries: {}),
        translateChunk: _fakeTranslate,
        onChunkResult: (itemLabel, result) => labels.add(itemLabel),
      );

      expect(labels, ['amod:guide']);
    });

    test('onItemStarted が処理着手ごとに本のキー(modId:bookId)を通知する(Issue#7)', () async {
      final entryA = _entry('amod', 'guide', {'book.json#0': '1'});
      final entryB = _entry('bmod', 'guide', {'book.json#0': '1'});
      final started = <String>[];

      await translatePatchouliBooks(
        selectedEntries: [entryA, entryB],
        policy: ExistingTranslationPolicy.retranslateAll,
        loadExistingTargetEntries: (_) async =>
            const PatchouliExistingTranslation(isComplete: false, entries: {}),
        translateChunk: _fakeTranslate,
        onItemStarted: started.add,
      );

      expect(started, ['amod:guide', 'bmod:guide']);
    });
  });
}
