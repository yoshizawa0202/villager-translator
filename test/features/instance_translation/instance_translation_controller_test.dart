import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:villager_translator/domain/instancetranslation/instance_translation_mode.dart';
import 'package:villager_translator/domain/instancetranslation/instance_translation_outcome.dart';
import 'package:villager_translator/domain/llm/llm_provider.dart';
import 'package:villager_translator/domain/minecraftinstance/instance_analysis.dart';
import 'package:villager_translator/domain/settings/existing_translation_policy.dart';
import 'package:villager_translator/features/instance_translation/instance_translation_controller.dart';
import 'package:villager_translator/features/settings/settings_controller.dart';
import 'package:villager_translator/infrastructure/instancetranslation/instance_translation_orchestrator.dart';

import '../../test_support/in_memory_api_key_store.dart';
import '../../test_support/in_memory_settings_repository.dart';
import '../../test_support/instance_translation_fixtures.dart';
import '../../test_support/recording_orchestrators.dart';

void main() {
  late Directory tempDir;
  late OrchestratorRecorder recorder;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('instance_translation_');
    recorder = OrchestratorRecorder();
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  Future<SettingsController> buildSettings({String apiKey = 'test-key'}) async {
    final controller = SettingsController(
      repository: InMemorySettingsRepository(),
      apiKeyStore: InMemoryApiKeyStore(),
    );
    await controller.load();
    if (apiKey.isNotEmpty) {
      await controller.setApiKey(LlmProvider.openai, apiKey);
    }
    return controller;
  }

  InstanceAnalysis buildAnalysis({
    int modCount = 2,
    int questCount = 1,
    int guidebookCount = 1,
  }) => InstanceAnalysis(
    instance: buildTestInstance(rootPath: tempDir.path),
    modJarCount: modCount,
    mods: [for (var i = 0; i < modCount; i++) buildModEntry(id: 'mod$i')],
    quests: [
      for (var i = 0; i < questCount; i++)
        buildQuestEntry(relativePath: 'q$i.json'),
    ],
    guidebooks: [
      for (var i = 0; i < guidebookCount; i++)
        buildBookEntry(modId: 'mod$i', bookId: 'book$i'),
    ],
  );

  Future<InstanceTranslationController> buildController({
    SettingsController? settings,
    InstanceAnalysis? analysis,
    InstanceTranslationOrchestrator? orchestrator,
    List<String> sessionIds = const ['session-1', 'session-2'],
  }) async {
    var index = 0;
    return InstanceTranslationController(
      settingsController: settings ?? await buildSettings(),
      analysis: analysis ?? buildAnalysis(),
      orchestrator:
          orchestrator ??
          InstanceTranslationOrchestrator(
            modOrchestrator: RecordingModOrchestrator(recorder),
            questOrchestrator: RecordingQuestOrchestrator(recorder),
            patchouliOrchestrator: RecordingPatchouliOrchestrator(recorder),
          ),
      sessionIdGenerator: () =>
          sessionIds[index++ < sessionIds.length ? index - 1 : 0],
      targetLanguageId: 'ja_jp',
    );
  }

  test('0 件のカテゴリは既定で OFF になり、切り替えもできない(012 AC-02)', () async {
    final controller = await buildController(
      analysis: buildAnalysis(modCount: 2, questCount: 0, guidebookCount: 0),
    );

    expect(controller.translateMods, isTrue);
    expect(controller.translateQuests, isFalse);
    expect(controller.translateGuidebooks, isFalse);

    controller.setTranslateQuests(true);
    expect(controller.translateQuests, isFalse);
  });

  test('全カテゴリ OFF のとき実行できない(012 AC-02)', () async {
    final controller = await buildController();

    controller
      ..setTranslateMods(false)
      ..setTranslateQuests(false)
      ..setTranslateGuidebooks(false);

    expect(controller.canTranslate, isFalse);

    await controller.translate();
    expect(recorder.calls, isEmpty);
  });

  test('API キー未設定なら日本語のエラーで実行されない(012 AC-05)', () async {
    final controller = await buildController(
      settings: await buildSettings(apiKey: ''),
    );

    await controller.translate();

    expect(controller.errorMessage, contains('API キーが未設定です'));
    expect(recorder.calls, isEmpty);
  });

  test('実行時の選択は保存済み設定へ書き戻さない(012 AC-04)', () async {
    final settings = await buildSettings();
    final controller = await buildController(settings: settings);

    controller
      ..setMode(InstanceTranslationMode.retranslateAll)
      ..setProvider(LlmProvider.gemini);

    // プロバイダーを切り替えたら、そのプロバイダーの API キーが必要になる。
    await settings.setApiKey(LlmProvider.gemini, 'gemini-key');
    await controller.translate();

    expect(recorder.calls, isNotEmpty);
    expect(
      settings.settings.translation.existingTranslationPolicy,
      ExistingTranslationPolicy.diffUpdate,
    );
    expect(settings.settings.llm.provider, LlmProvider.openai);
  });

  test('翻訳前サマリーの集計を計画から導出する(012 AC-06)', () async {
    final controller = await buildController(
      analysis: buildAnalysis(modCount: 2, questCount: 1, guidebookCount: 1),
    );

    final estimate = controller.buildEstimate();

    expect(estimate.totalItemCount, 4);
    expect(estimate.totalStringCount, 4);
    expect(estimate.categories.map((c) => c.label).toList(), [
      'MOD',
      'クエスト',
      'ガイドブック',
    ]);
  });

  test('全体進捗はカテゴリ別進捗の合算になる(012 AC-10)', () async {
    final controller = await buildController(
      analysis: buildAnalysis(modCount: 2, questCount: 1, guidebookCount: 0),
      orchestrator: InstanceTranslationOrchestrator(
        modOrchestrator: RecordingModOrchestrator(
          recorder,
          translatedPaths: ['mod0.jar', 'mod1.jar'],
        ),
        questOrchestrator: RecordingQuestOrchestrator(
          recorder,
          translatedPaths: ['q0.json'],
        ),
        patchouliOrchestrator: RecordingPatchouliOrchestrator(recorder),
      ),
    );

    await controller.translate();

    expect(controller.overallProgress.completedItems, 3);
    expect(controller.overallProgress.totalItems, 3);
    expect(
      controller.progressFor(InstanceTranslationCategory.mods)!.completedItems,
      2,
    );
  });

  test('完了後に成功・失敗・スキップ件数が結果へ集約される(012 AC-13)', () async {
    final controller = await buildController(
      analysis: buildAnalysis(modCount: 3, questCount: 0, guidebookCount: 0),
      orchestrator: InstanceTranslationOrchestrator(
        modOrchestrator: RecordingModOrchestrator(
          recorder,
          translatedPaths: ['mod0.jar'],
          failedPaths: ['mod1.jar'],
          skippedPaths: ['mod2.jar'],
        ),
        questOrchestrator: RecordingQuestOrchestrator(recorder),
        patchouliOrchestrator: RecordingPatchouliOrchestrator(recorder),
      ),
    );

    await controller.translate();

    expect(controller.state, InstanceTranslationState.completed);
    expect(controller.lastOutcome!.successCount, 1);
    expect(controller.lastOutcome!.failureCount, 1);
    expect(controller.lastOutcome!.skippedCount, 1);
    expect(controller.lastOutcome!.hasFailures, isTrue);
  });

  test('失敗項目の再試行は失敗対象だけを新しい sessionId で実行する(012 AC-13)', () async {
    final controller = await buildController(
      analysis: buildAnalysis(modCount: 3, questCount: 0, guidebookCount: 0),
      orchestrator: InstanceTranslationOrchestrator(
        modOrchestrator: RecordingModOrchestrator(
          recorder,
          translatedPaths: ['mod0.jar'],
          failedPaths: ['mod1.jar'],
          skippedPaths: ['mod2.jar'],
        ),
        questOrchestrator: RecordingQuestOrchestrator(recorder),
        patchouliOrchestrator: RecordingPatchouliOrchestrator(recorder),
      ),
    );

    await controller.translate();
    await controller.retryFailed();

    expect(recorder.calls, hasLength(2));
    // 1 回目は 3 件、再試行は失敗した 1 件だけ。
    expect(recorder.calls[0].itemCount, 3);
    expect(recorder.calls[1].itemCount, 1);
    // 元のセッションのログ・バックアップを上書きしない。
    expect(recorder.calls[0].sessionId, 'session-1');
    expect(recorder.calls[1].sessionId, 'session-2');
  });

  test('セッションログ開始行にプロバイダー ID とモデル名を記録する(012 AC-17)', () async {
    final controller = await buildController();

    await controller.translate();

    final messages = controller.sessionLogger.entries
        .map((e) => e.message)
        .toList();
    expect(
      messages.any(
        (m) => m.contains('プロバイダー openai') && m.contains('モデル gpt-5.6-luna'),
      ),
      isTrue,
    );
    // API キーは記録しない。
    expect(messages.any((m) => m.contains('test-key')), isFalse);
  });

  test('Minecraft バージョンから pack_format を判定して表示できる(012 AC-14)', () async {
    final controller = await buildController();

    expect(controller.packFormat.packFormat, 15);
    expect(controller.packFormat.isEstimated, isFalse);
    expect(controller.packFormat.isFallback, isFalse);
  });
}
