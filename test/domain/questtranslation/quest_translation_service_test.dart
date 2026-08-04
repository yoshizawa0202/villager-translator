import 'package:flutter_test/flutter_test.dart';
import 'package:villager_translator/domain/common/cancellation_token.dart';
import 'package:villager_translator/domain/questtranslation/quest_scan_entry.dart';
import 'package:villager_translator/domain/questtranslation/quest_translation_service.dart';
import 'package:villager_translator/domain/settings/existing_translation_policy.dart';

QuestScanEntry _jsonEntry(
  String path,
  Map<String, String> sourceEntries, {
  QuestFormat format = QuestFormat.betterQuestingStandard,
}) {
  return QuestScanEntry(
    format: format,
    relativePath: path,
    sourceEntries: sourceEntries,
  );
}

QuestScanEntry _snbtEntry(String path, Map<String, String> sourceEntries) {
  return QuestScanEntry(
    format: QuestFormat.ftbQuestsSnbt,
    relativePath: path,
    sourceEntries: sourceEntries,
    snbtOriginalContent: 'dummy',
    snbtSpans: const [],
  );
}

void main() {
  group('translateQuestEntries', () {
    test('JSON/LANG は差分更新方針で不足キーのみ翻訳される(受け入れ条件10)', () async {
      final entry = _jsonEntry('resources/betterquesting/lang/en_us.json', {
        'a': '1',
        'b': '2',
      });

      final result = await translateQuestEntries(
        selectedEntries: [entry],
        policy: ExistingTranslationPolicy.diffUpdate,
        loadExistingTargetEntries: (_) async => {'a': '既存訳'},
        translateChunk: (chunk) async =>
            chunk.map((k, v) => MapEntry(k, '[訳]$v')),
      );

      expect(result.translatedPaths, [entry.relativePath]);
      expect(result.outputs.single.entries, {'a': '既存訳', 'b': '[訳]2'});
    });

    test('JSON/LANG はスキップ方針で既存があればスキップされる(受け入れ条件10)', () async {
      final entry = _jsonEntry(
        'config/betterquesting/DefaultQuests.lang',
        {'a': '1'},
        format: QuestFormat.betterQuestingDirect,
      );

      final result = await translateQuestEntries(
        selectedEntries: [entry],
        policy: ExistingTranslationPolicy.skip,
        loadExistingTargetEntries: (_) async => {'a': '既存訳'},
        translateChunk: (chunk) async =>
            chunk.map((k, v) => MapEntry(k, '[訳]$v')),
      );

      expect(result.skippedPaths, [entry.relativePath]);
      expect(result.outputs, isEmpty);
    });

    test('JSON/LANG は全て再翻訳方針で既存があっても全キー翻訳される(受け入れ条件10)', () async {
      final entry = _jsonEntry(
        'kubejs/assets/kubejs/lang/en_us.json',
        {'a': '1', 'b': '2'},
        format: QuestFormat.ftbQuestsKubejsLang,
      );

      final result = await translateQuestEntries(
        selectedEntries: [entry],
        policy: ExistingTranslationPolicy.retranslateAll,
        loadExistingTargetEntries: (_) async => {'a': '既存訳のまま残ってはいけない'},
        translateChunk: (chunk) async =>
            chunk.map((k, v) => MapEntry(k, '[訳]$v')),
      );

      expect(result.outputs.single.entries, {'a': '[訳]1', 'b': '[訳]2'});
    });

    test('SNBT は既存翻訳判定が不能なため、方針設定に関わらず常に全文再翻訳される(受け入れ条件11)', () async {
      final entry = _snbtEntry('config/ftbquests/quests/chapter.snbt', {
        '0': 'Title',
      });

      var loaderCalled = false;
      final result = await translateQuestEntries(
        selectedEntries: [entry],
        policy: ExistingTranslationPolicy.skip,
        loadExistingTargetEntries: (_) async {
          loaderCalled = true;
          return {'0': '既存があってもSNBTでは使われない'};
        },
        translateChunk: (chunk) async =>
            chunk.map((k, v) => MapEntry(k, '[訳]$v')),
      );

      expect(loaderCalled, isFalse, reason: 'SNBT では既存確認を行わない');
      expect(result.translatedPaths, [entry.relativePath]);
      expect(result.outputs.single.entries, {'0': '[訳]Title'});
    });

    test('ファイル全体が1つの翻訳単位として渡され、キー単位に分割されない(受け入れ条件12)', () async {
      final entry = _jsonEntry('resources/betterquesting/lang/en_us.json', {
        'a': '1',
        'b': '2',
        'c': '3',
      });

      final chunkSizes = <int>[];
      var callCount = 0;
      await translateQuestEntries(
        selectedEntries: [entry],
        policy: ExistingTranslationPolicy.retranslateAll,
        loadExistingTargetEntries: (_) async => null,
        translateChunk: (chunk) async {
          callCount++;
          chunkSizes.add(chunk.length);
          return chunk.map((k, v) => MapEntry(k, '[訳]$v'));
        },
      );

      expect(callCount, 1);
      expect(chunkSizes, [3]);
    });

    test('抽出対象が0件のクエストファイルはスキップされる', () async {
      final entry = _snbtEntry('config/ftbquests/quests/empty.snbt', {});

      final result = await translateQuestEntries(
        selectedEntries: [entry],
        policy: ExistingTranslationPolicy.retranslateAll,
        loadExistingTargetEntries: (_) async => null,
        translateChunk: (chunk) async => chunk,
      );

      expect(result.skippedPaths, [entry.relativePath]);
      expect(result.outputs, isEmpty);
    });

    test('キャンセル済みの場合、現在のファイルは完了させた上で以降のファイルは処理しない(受け入れ条件5)', () async {
      final token = CancellationToken();
      final entryA = _jsonEntry('a.json', {'a': '1'});
      final entryB = _jsonEntry('b.json', {'a': '1'});

      final result = await translateQuestEntries(
        selectedEntries: [entryA, entryB],
        policy: ExistingTranslationPolicy.retranslateAll,
        loadExistingTargetEntries: (_) async => null,
        translateChunk: (chunk) async {
          // entryA のチャンク翻訳が完了する直前にキャンセルする
          // (「実行中のチャンクは中断しない」ことを確認するため)。
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

      await translateQuestEntries(
        selectedEntries: [entryA, entryB],
        policy: ExistingTranslationPolicy.retranslateAll,
        loadExistingTargetEntries: (_) async => null,
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
  });
}
