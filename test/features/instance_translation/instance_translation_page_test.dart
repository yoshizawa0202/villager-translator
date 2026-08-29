import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:villager_translator/domain/llm/llm_provider.dart';
import 'package:villager_translator/domain/minecraftinstance/instance_analysis.dart';
import 'package:villager_translator/features/instance_detail/instance_analysis_controller.dart';
import 'package:villager_translator/features/instance_translation/instance_translation_controller.dart';
import 'package:villager_translator/features/instance_translation/instance_translation_page.dart';
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
    tempDir = await Directory.systemTemp.createTemp('instance_page_test_');
    recorder = OrchestratorRecorder();
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  InstanceAnalysis buildAnalysis({
    int modCount = 2,
    int questCount = 1,
    int guidebookCount = 0,
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

  Future<InstanceTranslationController> pumpPage(
    WidgetTester tester, {
    InstanceAnalysis? analysis,
    String apiKey = 'test-key',
  }) async {
    tester.view.physicalSize = const Size(1200, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final settingsController = SettingsController(
      repository: InMemorySettingsRepository(),
      apiKeyStore: InMemoryApiKeyStore(),
    );
    await settingsController.load();
    if (apiKey.isNotEmpty) {
      await settingsController.setApiKey(LlmProvider.openai, apiKey);
    }

    final resolved = analysis ?? buildAnalysis();
    final analysisController = InstanceAnalysisController(
      instance: resolved.instance,
      targetLanguageId: 'ja_jp',
    );

    final controller = InstanceTranslationController(
      settingsController: settingsController,
      analysis: resolved,
      targetLanguageId: 'ja_jp',
      orchestrator: InstanceTranslationOrchestrator(
        modOrchestrator: RecordingModOrchestrator(
          recorder,
          translatedPaths: ['mod0.jar'],
          failedPaths: ['mod1.jar'],
        ),
        questOrchestrator: RecordingQuestOrchestrator(
          recorder,
          translatedPaths: ['q0.json'],
        ),
        patchouliOrchestrator: RecordingPatchouliOrchestrator(recorder),
      ),
    );

    await tester.pumpWidget(
      ChangeNotifierProvider<SettingsController>.value(
        value: settingsController,
        child: MaterialApp(
          home: InstanceTranslationPage(
            analysisController: analysisController,
            controller: controller,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return controller;
  }

  testWidgets('0 件のカテゴリはチェックボックスが無効化される(012 AC-02)', (tester) async {
    await pumpPage(
      tester,
      analysis: buildAnalysis(modCount: 2, questCount: 0, guidebookCount: 0),
    );

    final quests = tester.widget<CheckboxListTile>(
      find.byKey(const Key('translateQuestsCheckbox')),
    );
    final guidebooks = tester.widget<CheckboxListTile>(
      find.byKey(const Key('translateGuidebooksCheckbox')),
    );
    final mods = tester.widget<CheckboxListTile>(
      find.byKey(const Key('translateModsCheckbox')),
    );

    expect(quests.onChanged, isNull);
    expect(guidebooks.onChanged, isNull);
    expect(mods.onChanged, isNotNull);
    expect(find.text('未検出'), findsNWidgets(2));
  });

  testWidgets('全カテゴリ OFF のとき「すべて翻訳」が無効化される(012 AC-02)', (tester) async {
    final controller = await pumpPage(tester);

    controller
      ..setTranslateMods(false)
      ..setTranslateQuests(false)
      ..setTranslateGuidebooks(false);
    await tester.pumpAndSettle();

    final button = tester.widget<FilledButton>(
      find.byKey(const Key('translateAllButton')),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('「すべて翻訳」で翻訳前サマリーが表示され、「戻る」で実行されない(012 AC-06)', (tester) async {
    await pumpPage(tester);

    await tester.tap(find.byKey(const Key('translateAllButton')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('instanceTranslationSummaryDialog')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('summaryCategory_MOD')), findsOneWidget);
    expect(find.byKey(const Key('summaryTotalStringCount')), findsOneWidget);
    expect(find.byKey(const Key('summaryModelLabel')), findsOneWidget);
    expect(find.byKey(const Key('summaryLanguageLabel')), findsOneWidget);
    // 既定は差分更新のため、上限値である旨を注記する。
    expect(find.byKey(const Key('summaryUpperBoundNote')), findsOneWidget);

    await tester.tap(
      find.byKey(const Key('instanceTranslationSummaryBackButton')),
    );
    await tester.pumpAndSettle();

    expect(recorder.calls, isEmpty);
  });

  testWidgets('「翻訳開始」で実行され、完了画面に件数と再試行が表示される(012 AC-13、AC-16)', (tester) async {
    final controller = await pumpPage(tester);

    // 実行はセッションログの書き出し(実ファイル I/O)を伴うため、
    // 既存の翻訳画面テストと同じく runAsync でコントローラーを直接駆動する
    // (fake-async 環境の pump は実 I/O の完了を待てないため)。
    await tester.runAsync(controller.translate);
    await tester.pumpAndSettle();

    expect(recorder.calls.map((c) => c.category).toList(), ['mods', 'quests']);

    expect(
      find.byKey(const Key('instanceTranslationCompletionDialog')),
      findsOneWidget,
    );
    expect(
      tester
          .widget<Text>(find.byKey(const Key('instanceCompletionCounts')))
          .data,
      '成功 2 件 / 失敗 1 件 / スキップ 0 件',
    );
    expect(find.byKey(const Key('retryFailedItemsButton')), findsOneWidget);
    expect(find.byKey(const Key('completionCategory_mods')), findsOneWidget);
    expect(
      find.byKey(const Key('completionCategory_guidebooks')),
      findsOneWidget,
    );
  });

  testWidgets('API キー未設定なら日本語のエラーが表示され実行されない(012 AC-05)', (tester) async {
    await pumpPage(tester, apiKey: '');

    await tester.tap(find.byKey(const Key('translateAllButton')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('instanceTranslationSummaryStartButton')),
    );
    await tester.pumpAndSettle();

    expect(recorder.calls, isEmpty);
    expect(
      find.byKey(const Key('instanceTranslationErrorMessage')),
      findsOneWidget,
    );
    expect(find.textContaining('API キーが未設定です'), findsOneWidget);
  });

  testWidgets('判定した pack_format を画面に表示する(012 AC-14)', (tester) async {
    await pumpPage(tester);

    expect(
      tester
          .widget<Text>(find.byKey(const Key('instancePackFormatLabel')))
          .data,
      contains('pack_format: 15'),
    );
  });
}
