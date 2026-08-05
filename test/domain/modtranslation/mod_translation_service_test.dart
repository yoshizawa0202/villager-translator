import 'package:flutter_test/flutter_test.dart';
import 'package:villager_translator/domain/common/cancellation_token.dart';
import 'package:villager_translator/domain/common/translation_progress.dart';
import 'package:villager_translator/domain/modtranslation/mod_info.dart';
import 'package:villager_translator/domain/modtranslation/mod_scan_entry.dart';
import 'package:villager_translator/domain/modtranslation/mod_translation_service.dart';
import 'package:villager_translator/domain/settings/existing_translation_policy.dart';
import 'package:villager_translator/domain/translation/lang_codec.dart';

ModScanEntry _entry(
  String modId,
  Map<String, String> sourceEntries, {
  bool hasExistingTranslation = false,
}) {
  return ModScanEntry(
    modInfo: ModInfo(
      id: modId,
      name: modId,
      version: '1.0',
      source: ModInfoSource.fabricModJson,
    ),
    jarRelativePath: '$modId.jar',
    langFormat: LangFormat.json,
    sourceLangPath: 'assets/$modId/lang/en_us.json',
    sourceEntries: sourceEntries,
    hasExistingTranslation: hasExistingTranslation,
  );
}

Future<Map<String, String>> _fakeTranslate(Map<String, String> chunk) async {
  return chunk.map((key, value) => MapEntry(key, '[訳]$value'));
}

List<Map<String, String>> _singleChunk(Map<String, String> entries) =>
    entries.isEmpty ? [] : [entries];

void main() {
  group('translateSelectedMods', () {
    test('スキップ方針: 既存翻訳を持つ MOD はスキップ件数としてカウントされる(受け入れ条件8)', () async {
      final withExisting = _entry('modb', {'a': '1'});
      final withoutExisting = _entry('moda', {'a': '1'});

      final result = await translateSelectedMods(
        selectedEntries: [withExisting, withoutExisting],
        policy: ExistingTranslationPolicy.skip,
        loadExistingTargetEntries: (entry) async =>
            entry.modInfo.id == 'modb' ? {'a': '既存'} : null,
        chunkEntries: _singleChunk,
        translateChunk: _fakeTranslate,
      );

      expect(result.skippedModIds, ['modb']);
      expect(result.translatedModIds, ['moda']);
      expect(result.outputs.single.modId, 'moda');
      expect(result.outputs.single.entries, {'a': '[訳]1'});
    });

    test('差分更新方針: 不足キーのみ翻訳され、既存キーの値は変更されない(受け入れ条件9)', () async {
      final entry = _entry('modc', {'a': '1', 'b': '2', 'c': '3'});

      final result = await translateSelectedMods(
        selectedEntries: [entry],
        policy: ExistingTranslationPolicy.diffUpdate,
        loadExistingTargetEntries: (_) async => {'a': '手動修正済み'},
        chunkEntries: _singleChunk,
        translateChunk: _fakeTranslate,
      );

      expect(result.translatedModIds, ['modc']);
      expect(result.outputs.single.entries, {
        'a': '手動修正済み',
        'b': '[訳]2',
        'c': '[訳]3',
      });
    });

    test('差分更新方針: 不足キーが1件もない場合はスキップ扱いになる(受け入れ条件9,11)', () async {
      final entry = _entry('modd', {'a': '1'});

      final result = await translateSelectedMods(
        selectedEntries: [entry],
        policy: ExistingTranslationPolicy.diffUpdate,
        loadExistingTargetEntries: (_) async => {'a': '既存訳'},
        chunkEntries: _singleChunk,
        translateChunk: _fakeTranslate,
      );

      expect(result.skippedModIds, ['modd']);
      expect(result.outputs, isEmpty);
      expect(result.hasOutputs, isFalse);
    });

    test('全て再翻訳方針: 既存の有無に関わらず全キーが翻訳される(受け入れ条件10)', () async {
      final entry = _entry('mode', {'a': '1', 'b': '2'});

      final result = await translateSelectedMods(
        selectedEntries: [entry],
        policy: ExistingTranslationPolicy.retranslateAll,
        loadExistingTargetEntries: (_) async => {'a': '既存訳のまま残ってはいけない'},
        chunkEntries: _singleChunk,
        translateChunk: _fakeTranslate,
      );

      expect(result.translatedModIds, ['mode']);
      expect(result.outputs.single.entries, {'a': '[訳]1', 'b': '[訳]2'});
    });

    test('選択した全対象がスキップの場合、outputs が空になる(受け入れ条件11)', () async {
      final entryA = _entry('moda', {'a': '1'});
      final entryB = _entry('modb', {'a': '1'});

      final result = await translateSelectedMods(
        selectedEntries: [entryA, entryB],
        policy: ExistingTranslationPolicy.skip,
        loadExistingTargetEntries: (_) async => {'a': '既存'},
        chunkEntries: _singleChunk,
        translateChunk: _fakeTranslate,
      );

      expect(result.outputs, isEmpty);
      expect(result.hasOutputs, isFalse);
      expect(result.skippedModIds, ['moda', 'modb']);
    });

    test('MOD ID のアルファベット順に処理される(受け入れ条件7)', () async {
      final processedOrder = <String>[];
      final entryZ = _entry('zmod', {'a': '1'});
      final entryA = _entry('amod', {'a': '1'});

      await translateSelectedMods(
        selectedEntries: [entryZ, entryA],
        policy: ExistingTranslationPolicy.retranslateAll,
        loadExistingTargetEntries: (entry) async {
          processedOrder.add(entry.modInfo.id);
          return null;
        },
        chunkEntries: _singleChunk,
        translateChunk: _fakeTranslate,
      );

      expect(processedOrder, ['amod', 'zmod']);
    });

    test('キャンセル済みの場合、以降の MOD の処理を開始しない(受け入れ条件5)', () async {
      final token = CancellationToken();
      final entryA = _entry('amod', {'a': '1'});
      final entryB = _entry('bmod', {'a': '1'});
      final processed = <String>[];

      final result = await translateSelectedMods(
        selectedEntries: [entryA, entryB],
        policy: ExistingTranslationPolicy.retranslateAll,
        loadExistingTargetEntries: (entry) async {
          processed.add(entry.modInfo.id);
          if (entry.modInfo.id == 'amod') token.cancel();
          return null;
        },
        chunkEntries: _singleChunk,
        translateChunk: _fakeTranslate,
        cancellationToken: token,
      );

      expect(processed, ['amod']);
      expect(result.translatedModIds, ['amod']);
    });

    test('進捗コールバックが対象1件ごとに完了件数/総件数を通知する', () async {
      final entryA = _entry('amod', {'a': '1'});
      final entryB = _entry('bmod', {'a': '1'});
      final overallUpdates = <List<int>>[];

      await translateSelectedMods(
        selectedEntries: [entryA, entryB],
        policy: ExistingTranslationPolicy.retranslateAll,
        loadExistingTargetEntries: (_) async => null,
        chunkEntries: _singleChunk,
        translateChunk: _fakeTranslate,
        onOverallProgress: (progress) =>
            overallUpdates.add([progress.completedItems, progress.totalItems]),
      );

      expect(overallUpdates, [
        [1, 2],
        [2, 2],
      ]);
    });

    test('単一ファイル進捗コールバックがチャンク完了ごとに通知される', () async {
      final entry = _entry('amod', {'a': '1', 'b': '2'});
      List<Map<String, String>> chunkedByKey(Map<String, String> entries) =>
          entries.entries.map((e) => {e.key: e.value}).toList();
      final fileProgressUpdates = <ChunkProgress>[];

      await translateSelectedMods(
        selectedEntries: [entry],
        policy: ExistingTranslationPolicy.retranslateAll,
        loadExistingTargetEntries: (_) async => null,
        chunkEntries: chunkedByKey,
        translateChunk: _fakeTranslate,
        onSingleFileProgress: fileProgressUpdates.add,
      );

      expect(fileProgressUpdates.map((p) => p.completedChunks), [1, 2]);
      expect(fileProgressUpdates.map((p) => p.totalChunks), [2, 2]);
    });

    test('onChunkResult が MOD 名付きでチャンク単位の結果を通知する(Issue#10)', () async {
      final entry = _entry('amod', {'a': '1'});
      final results = <String>[];

      await translateSelectedMods(
        selectedEntries: [entry],
        policy: ExistingTranslationPolicy.retranslateAll,
        loadExistingTargetEntries: (_) async => null,
        chunkEntries: _singleChunk,
        translateChunk: _fakeTranslate,
        onChunkResult: (itemLabel, result) => results.add(itemLabel),
      );

      expect(results, ['amod']);
    });

    test('onChunkResult がチャンクの失敗を MOD 名付きで通知する(Issue#10)', () async {
      final entry = _entry('failmod', {'a': '1'});
      final received = <ChunkResult>[];

      await translateSelectedMods(
        selectedEntries: [entry],
        policy: ExistingTranslationPolicy.retranslateAll,
        loadExistingTargetEntries: (_) async => null,
        chunkEntries: _singleChunk,
        translateChunk: (chunk) async => throw Exception('翻訳失敗'),
        maxRetries: 0,
        waiter: (_) async {},
        onChunkResult: (itemLabel, result) {
          expect(itemLabel, 'failmod');
          received.add(result);
        },
      );

      expect(received, hasLength(1));
      expect(received.single.success, isFalse);
    });
  });
}
