import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:villager_translator/domain/common/cancellation_token.dart';
import 'package:villager_translator/domain/common/translation_progress.dart';
import 'package:villager_translator/domain/common/translation_summary.dart';
import 'package:villager_translator/domain/instancetranslation/instance_translation_mode.dart';
import 'package:villager_translator/domain/instancetranslation/instance_translation_outcome.dart';
import 'package:villager_translator/domain/llm/llm_provider.dart';
import 'package:villager_translator/domain/settings/app_settings.dart';
import 'package:villager_translator/domain/settings/existing_translation_policy.dart';
import 'package:villager_translator/infrastructure/common/session_paths.dart';
import 'package:villager_translator/infrastructure/common/translation_summary_writer.dart';
import 'package:villager_translator/infrastructure/instancetranslation/instance_translation_orchestrator.dart';

import '../../test_support/instance_translation_fixtures.dart';
import '../../test_support/recording_orchestrators.dart';

void main() {
  late Directory tempDir;
  late OrchestratorRecorder recorder;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('instance_orchestrator_');
    recorder = OrchestratorRecorder();
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  InstanceTranslationOrchestrator buildOrchestrator({
    RecordingModOrchestrator? mod,
    RecordingQuestOrchestrator? quest,
    RecordingPatchouliOrchestrator? patchouli,
  }) => InstanceTranslationOrchestrator(
    modOrchestrator: mod ?? RecordingModOrchestrator(recorder),
    questOrchestrator: quest ?? RecordingQuestOrchestrator(recorder),
    patchouliOrchestrator:
        patchouli ?? RecordingPatchouliOrchestrator(recorder),
  );

  test('MOD → クエスト → ガイドブックの順に呼ばれる(012 AC-07)', () async {
    await buildOrchestrator().translate(
      plan: buildTestPlan(
        rootPath: tempDir.path,
        mods: [buildModEntry(id: 'a')],
        quests: [buildQuestEntry(relativePath: 'q.json')],
        guidebooks: [buildBookEntry(modId: 'ars', bookId: 'notebook')],
      ),
      settings: AppSettings.defaults(),
      apiKey: 'key',
      sessionId: 'session-1',
    );

    expect(recorder.calls.map((c) => c.category).toList(), [
      'mods',
      'quests',
      'guidebooks',
    ]);
  });

  test('OFF にしたカテゴリのオーケストレーターは呼ばれない(012 AC-02)', () async {
    await buildOrchestrator().translate(
      plan: buildTestPlan(
        rootPath: tempDir.path,
        mods: [buildModEntry(id: 'a')],
        quests: [buildQuestEntry(relativePath: 'q.json')],
        guidebooks: [buildBookEntry(modId: 'ars', bookId: 'notebook')],
        translateQuests: false,
        translateGuidebooks: false,
      ),
      settings: AppSettings.defaults(),
      apiKey: 'key',
      sessionId: 'session-1',
    );

    expect(recorder.calls.map((c) => c.category).toList(), ['mods']);
  });

  test('3 カテゴリへ同一の sessionId と CancellationToken が渡る(012 AC-08)', () async {
    final token = CancellationToken();

    await buildOrchestrator().translate(
      plan: buildTestPlan(
        rootPath: tempDir.path,
        mods: [buildModEntry(id: 'a')],
        quests: [buildQuestEntry(relativePath: 'q.json')],
        guidebooks: [buildBookEntry(modId: 'ars', bookId: 'notebook')],
      ),
      settings: AppSettings.defaults(),
      apiKey: 'key',
      sessionId: 'session-1',
      cancellationToken: token,
    );

    expect(recorder.calls.map((c) => c.sessionId).toSet(), {'session-1'});
    for (final call in recorder.calls) {
      expect(identical(call.cancellationToken, token), isTrue);
    }
  });

  test('翻訳モード・プロバイダー・モデルが実行時上書きとして渡る(012 AC-03、AC-04)', () async {
    final base = AppSettings.defaults();

    await buildOrchestrator().translate(
      plan: buildTestPlan(
        rootPath: tempDir.path,
        mods: [buildModEntry(id: 'a')],
        translateQuests: false,
        translateGuidebooks: false,
        mode: InstanceTranslationMode.retranslateAll,
        provider: LlmProvider.gemini,
        model: 'gemini-3.7-flash',
      ),
      settings: base,
      apiKey: 'key',
      sessionId: 'session-1',
    );

    final passed = recorder.calls.single.settings;
    expect(
      passed.translation.existingTranslationPolicy,
      ExistingTranslationPolicy.retranslateAll,
    );
    expect(passed.llm.provider, LlmProvider.gemini);
    expect(passed.llm.effectiveModel, 'gemini-3.7-flash');

    // 保存済み設定そのものは変更されない。
    expect(
      base.translation.existingTranslationPolicy,
      ExistingTranslationPolicy.diffUpdate,
    );
    expect(base.llm.provider, LlmProvider.openai);
  });

  test('Minecraft バージョンから判定した pack_format が MOD 経路へ渡る(012 AC-14)', () async {
    await buildOrchestrator().translate(
      plan: buildTestPlan(
        rootPath: tempDir.path,
        minecraftVersion: '1.21.1',
        mods: [buildModEntry(id: 'a')],
        translateQuests: false,
        translateGuidebooks: false,
      ),
      settings: AppSettings.defaults(),
      apiKey: 'key',
      sessionId: 'session-1',
    );

    expect(recorder.calls.single.packFormat, 34);
  });

  test('1 カテゴリが例外を投げても後続カテゴリが実行される(012 AC-12)', () async {
    final outcome =
        await buildOrchestrator(
          mod: RecordingModOrchestrator(
            recorder,
            error: const FormatException('MOD 翻訳が失敗しました'),
          ),
          quest: RecordingQuestOrchestrator(
            recorder,
            translatedPaths: ['q.json'],
          ),
        ).translate(
          plan: buildTestPlan(
            rootPath: tempDir.path,
            mods: [
              buildModEntry(id: 'a'),
              buildModEntry(id: 'b'),
            ],
            quests: [buildQuestEntry(relativePath: 'q.json')],
            guidebooks: [buildBookEntry(modId: 'ars', bookId: 'notebook')],
          ),
          settings: AppSettings.defaults(),
          apiKey: 'key',
          sessionId: 'session-1',
        );

    expect(recorder.calls.map((c) => c.category).toList(), [
      'mods',
      'quests',
      'guidebooks',
    ]);

    final mods = outcome.outcomeFor(InstanceTranslationCategory.mods)!;
    expect(mods.error, isA<FormatException>());
    // 例外で終わったカテゴリの対象はすべて失敗として記録する。
    expect(mods.failedIds, ['a.jar', 'b.jar']);

    final quests = outcome.outcomeFor(InstanceTranslationCategory.quests)!;
    expect(quests.successIds, ['q.json']);
  });

  test('全カテゴリ完了後に統合サマリーが 1 回書き出される(012 AC-09)', () async {
    final outcome =
        await buildOrchestrator(
          mod: RecordingModOrchestrator(recorder, translatedPaths: ['a.jar']),
          quest: RecordingQuestOrchestrator(
            recorder,
            translatedPaths: ['q.json'],
          ),
          patchouli: RecordingPatchouliOrchestrator(
            recorder,
            translatedBookKeys: ['ars:notebook'],
          ),
        ).translate(
          plan: buildTestPlan(
            rootPath: tempDir.path,
            mods: [buildModEntry(id: 'a')],
            quests: [buildQuestEntry(relativePath: 'q.json')],
            guidebooks: [buildBookEntry(modId: 'ars', bookId: 'notebook')],
          ),
          settings: AppSettings.defaults(),
          apiKey: 'key',
          sessionId: 'session-1',
        );

    expect(outcome.summary.items.map((i) => i.id).toList(), [
      'a.jar',
      'q.json',
      'ars:notebook',
    ]);

    // 既存規約どおり {rootPath}/logs/localizer/{sessionId}/ 配下へ集約される。
    final summaryFile = SessionPaths(
      profileDirectory: tempDir,
      sessionId: 'session-1',
    ).summaryFile;
    expect(await summaryFile.exists(), isTrue);

    final written =
        jsonDecode(await summaryFile.readAsString()) as Map<String, dynamic>;
    expect(written['sessionId'], 'session-1');
    expect((written['items'] as List), hasLength(3));
  });

  test('キャンセル時にも統合サマリーが書かれ、後続カテゴリは開始されない(012 AC-11)', () async {
    final token = CancellationToken();

    final outcome =
        await buildOrchestrator(
          mod: RecordingModOrchestrator(
            recorder,
            translatedPaths: ['a.jar'],
            // MOD 処理中にキャンセルされた状況を再現する。
            onCall: token.cancel,
          ),
        ).translate(
          plan: buildTestPlan(
            rootPath: tempDir.path,
            mods: [buildModEntry(id: 'a')],
            quests: [buildQuestEntry(relativePath: 'q.json')],
            guidebooks: [buildBookEntry(modId: 'ars', bookId: 'notebook')],
          ),
          settings: AppSettings.defaults(),
          apiKey: 'key',
          sessionId: 'session-1',
          cancellationToken: token,
        );

    expect(recorder.calls.map((c) => c.category).toList(), ['mods']);
    expect(outcome.cancelled, isTrue);
    expect(
      outcome.outcomeFor(InstanceTranslationCategory.quests)!.executed,
      isFalse,
    );

    final summaryFile = SessionPaths(
      profileDirectory: tempDir,
      sessionId: 'session-1',
    ).summaryFile;
    expect(await summaryFile.exists(), isTrue);
  });

  test('カテゴリ別進捗を通知し、全体進捗は合算になる(012 AC-10)', () async {
    final categoryProgress = <InstanceTranslationCategory, OverallProgress>{};

    await buildOrchestrator(
      mod: RecordingModOrchestrator(
        recorder,
        translatedPaths: ['a.jar', 'b.jar'],
      ),
      quest: RecordingQuestOrchestrator(recorder, translatedPaths: ['q.json']),
    ).translate(
      plan: buildTestPlan(
        rootPath: tempDir.path,
        mods: [
          buildModEntry(id: 'a'),
          buildModEntry(id: 'b'),
        ],
        quests: [buildQuestEntry(relativePath: 'q.json')],
        translateGuidebooks: false,
      ),
      settings: AppSettings.defaults(),
      apiKey: 'key',
      sessionId: 'session-1',
      onCategoryProgress: (category, progress) =>
          categoryProgress[category] = progress,
    );

    expect(
      categoryProgress[InstanceTranslationCategory.mods]!.completedItems,
      2,
    );
    expect(
      categoryProgress[InstanceTranslationCategory.quests]!.completedItems,
      1,
    );

    final completed = categoryProgress.values.fold(
      0,
      (sum, p) => sum + p.completedItems,
    );
    final total = categoryProgress.values.fold(
      0,
      (sum, p) => sum + p.totalItems,
    );
    expect(completed, 3);
    expect(total, 3);
  });

  test('成功・失敗・スキップをカテゴリごとに集計する(012 §10)', () async {
    final outcome =
        await buildOrchestrator(
          mod: RecordingModOrchestrator(
            recorder,
            translatedPaths: ['a.jar'],
            failedPaths: ['b.jar'],
            skippedPaths: ['c.jar'],
          ),
          quest: RecordingQuestOrchestrator(
            recorder,
            translatedPaths: ['q.json'],
          ),
        ).translate(
          plan: buildTestPlan(
            rootPath: tempDir.path,
            mods: [
              buildModEntry(id: 'a'),
              buildModEntry(id: 'b'),
              buildModEntry(id: 'c'),
            ],
            quests: [buildQuestEntry(relativePath: 'q.json')],
            translateGuidebooks: false,
          ),
          settings: AppSettings.defaults(),
          apiKey: 'key',
          sessionId: 'session-1',
        );

    expect(outcome.successCount, 2);
    expect(outcome.failureCount, 1);
    expect(outcome.skippedCount, 1);

    final mods = outcome.outcomeFor(InstanceTranslationCategory.mods)!;
    expect(mods.successIds, ['a.jar']);
    expect(mods.failedIds, ['b.jar']);
    expect(mods.skippedIds, ['c.jar']);
    expect(mods.outputLocations.single, contains('resourcepacks'));
  });

  test('統合サマリーの書き出しに失敗しても完了済みカテゴリの結果は返る(012 AC-09)', () async {
    final errors = <Object>[];

    final outcome =
        await InstanceTranslationOrchestrator(
          modOrchestrator: RecordingModOrchestrator(
            recorder,
            translatedPaths: ['a.jar'],
          ),
          questOrchestrator: RecordingQuestOrchestrator(
            recorder,
            translatedPaths: ['q.json'],
          ),
          patchouliOrchestrator: RecordingPatchouliOrchestrator(recorder),
          summaryWriter: const _FailingSummaryWriter(),
        ).translate(
          plan: buildTestPlan(
            rootPath: tempDir.path,
            mods: [buildModEntry(id: 'a')],
            quests: [buildQuestEntry(relativePath: 'q.json')],
            translateGuidebooks: false,
          ),
          settings: AppSettings.defaults(),
          apiKey: 'key',
          sessionId: 'session-1',
          onSummaryWriteError: errors.add,
        );

    // 例外が伝播せず、3 カテゴリの結果がそのまま返る。
    expect(outcome.sessionId, 'session-1');
    expect(outcome.successCount, 2);
    expect(outcome.outcomeFor(InstanceTranslationCategory.mods)!.successIds, [
      'a.jar',
    ]);
    expect(outcome.summary.items, isNotEmpty);

    // 失敗は呼び出し元へ通知される(ログに残せる)。
    expect(errors.single, isA<FileSystemException>());
  });
}

/// 統合サマリーの書き出しが失敗する状況を再現する(012 AC-09)。
class _FailingSummaryWriter extends TranslationSummaryWriter {
  const _FailingSummaryWriter();

  @override
  Future<File> write({
    required Directory profileDirectory,
    required TranslationSummary summary,
  }) async {
    throw const FileSystemException('書き出しに失敗しました');
  }
}
