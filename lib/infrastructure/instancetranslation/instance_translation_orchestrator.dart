import 'dart:io';

import '../../domain/common/cancellation_token.dart';
import '../../domain/common/translation_progress.dart';
import '../../domain/common/translation_summary.dart';
import '../../domain/instancetranslation/instance_translation_outcome.dart';
import '../../domain/instancetranslation/instance_translation_plan.dart';
import '../../domain/instancetranslation/resource_pack_format.dart';
import '../../domain/settings/app_settings.dart';
import '../common/translation_summary_writer.dart';
import '../modtranslation/mod_translation_orchestrator.dart';
import '../patchoulitranslation/patchouli_translation_orchestrator.dart';
import '../questtranslation/quest_translation_orchestrator.dart';

/// カテゴリ別進捗の通知(012-instance-batch-translation.md §9)。
typedef CategoryProgressCallback =
    void Function(
      InstanceTranslationCategory category,
      OverallProgress progress,
    );

/// カテゴリの開始通知(§9)。
typedef CategoryStartedCallback =
    void Function(InstanceTranslationCategory category);

/// インスタンス一括翻訳を統括する上位オーケストレーター(§1、§7)。
///
/// 新しい翻訳ロジック(チャンク分割、応答検証、リトライ、出力生成、バックアップ)は
/// 一切追加しない。既存の 3 オーケストレーターを MOD → クエスト → ガイドブックの
/// 順に呼び、結果を集約することだけを責務とする。
class InstanceTranslationOrchestrator {
  InstanceTranslationOrchestrator({
    ModTranslationOrchestrator? modOrchestrator,
    QuestTranslationOrchestrator? questOrchestrator,
    PatchouliTranslationOrchestrator? patchouliOrchestrator,
    TranslationSummaryWriter summaryWriter = const TranslationSummaryWriter(),
  }) : _modOrchestrator = modOrchestrator ?? ModTranslationOrchestrator(),
       _questOrchestrator = questOrchestrator ?? QuestTranslationOrchestrator(),
       _patchouliOrchestrator =
           patchouliOrchestrator ?? PatchouliTranslationOrchestrator(),
       _summaryWriter = summaryWriter;

  final ModTranslationOrchestrator _modOrchestrator;
  final QuestTranslationOrchestrator _questOrchestrator;
  final PatchouliTranslationOrchestrator _patchouliOrchestrator;
  final TranslationSummaryWriter _summaryWriter;

  /// [plan] に従って一括翻訳を実行する。
  ///
  /// [settings] は保存済み設定。翻訳モード・プロバイダー・モデルは
  /// [AppSettings.copyWith] による実行時上書きとして適用し、`settings.json` へは
  /// 書き戻さない(§4、AC-04)。
  Future<InstanceTranslationOutcome> translate({
    required InstanceTranslationPlan plan,
    required AppSettings settings,
    required String apiKey,
    required String sessionId,
    CancellationToken? cancellationToken,
    CategoryStartedCallback? onCategoryStarted,
    CategoryProgressCallback? onCategoryProgress,
    SingleFileProgressCallback? onSingleFileProgress,
    ItemChunkResultCallback? onChunkResult,
    CurrentItemCallback? onItemStarted,
  }) async {
    final profileDirectory = Directory(plan.instance.rootPath);
    final effectiveSettings = _applyPlanOverrides(settings, plan);

    final outcomes = <InstanceTranslationCategoryOutcome>[];
    final summaryItems = <TranslationSummaryItem>[];

    // 1. MOD → 2. クエスト → 3. ガイドブック の直列固定(§7、AC-07)。
    outcomes.add(
      await _runMods(
        plan: plan,
        profileDirectory: profileDirectory,
        settings: effectiveSettings,
        apiKey: apiKey,
        sessionId: sessionId,
        cancellationToken: cancellationToken,
        summaryItems: summaryItems,
        onCategoryStarted: onCategoryStarted,
        onCategoryProgress: onCategoryProgress,
        onSingleFileProgress: onSingleFileProgress,
        onChunkResult: onChunkResult,
        onItemStarted: onItemStarted,
      ),
    );

    outcomes.add(
      await _runQuests(
        plan: plan,
        profileDirectory: profileDirectory,
        settings: effectiveSettings,
        apiKey: apiKey,
        sessionId: sessionId,
        cancellationToken: cancellationToken,
        summaryItems: summaryItems,
        onCategoryStarted: onCategoryStarted,
        onCategoryProgress: onCategoryProgress,
        onSingleFileProgress: onSingleFileProgress,
        onChunkResult: onChunkResult,
        onItemStarted: onItemStarted,
      ),
    );

    outcomes.add(
      await _runGuidebooks(
        plan: plan,
        profileDirectory: profileDirectory,
        settings: effectiveSettings,
        apiKey: apiKey,
        sessionId: sessionId,
        cancellationToken: cancellationToken,
        summaryItems: summaryItems,
        onCategoryStarted: onCategoryStarted,
        onCategoryProgress: onCategoryProgress,
        onSingleFileProgress: onSingleFileProgress,
        onChunkResult: onChunkResult,
        onItemStarted: onItemStarted,
      ),
    );

    // 4. 出力検証 → 5. 完了(§7)。
    // 3 カテゴリはそれぞれ同じ sessionId の translation_summary.json を書くため、
    // 最後に統合サマリーで 1 回書き直す(§8、AC-09)。キャンセル時・一部カテゴリの
    // 失敗時にも必ず書き出す。
    final summary = TranslationSummary(
      sessionId: sessionId,
      targetLanguage: plan.targetLanguageId,
      createdAt: DateTime.now(),
      items: summaryItems,
    );
    await _summaryWriter.write(
      profileDirectory: profileDirectory,
      summary: summary,
    );

    return InstanceTranslationOutcome(
      sessionId: sessionId,
      categories: outcomes,
      summary: summary,
      cancelled: cancellationToken?.isCancelled ?? false,
    );
  }

  /// 一括翻訳画面での選択を、この実行だけの上書きとして適用する(§4)。
  AppSettings _applyPlanOverrides(
    AppSettings settings,
    InstanceTranslationPlan plan,
  ) {
    return settings.copyWith(
      llm: settings.llm.copyWith(provider: plan.provider, model: plan.model),
      translation: settings.translation.copyWith(
        existingTranslationPolicy: plan.mode.policy,
      ),
    );
  }

  Future<InstanceTranslationCategoryOutcome> _runMods({
    required InstanceTranslationPlan plan,
    required Directory profileDirectory,
    required AppSettings settings,
    required String apiKey,
    required String sessionId,
    required CancellationToken? cancellationToken,
    required List<TranslationSummaryItem> summaryItems,
    required CategoryStartedCallback? onCategoryStarted,
    required CategoryProgressCallback? onCategoryProgress,
    required SingleFileProgressCallback? onSingleFileProgress,
    required ItemChunkResultCallback? onChunkResult,
    required CurrentItemCallback? onItemStarted,
  }) async {
    const category = InstanceTranslationCategory.mods;
    final selected = plan.effectiveMods;
    if (selected.isEmpty || (cancellationToken?.isCancelled ?? false)) {
      return InstanceTranslationCategoryOutcome.notExecuted(category);
    }

    onCategoryStarted?.call(category);

    // Minecraft バージョンが分かる経路なので pack_format を判定して渡す(§11)。
    final packFormat = resolveResourcePackFormat(
      plan.instance.minecraftVersion,
    );

    try {
      final result = await _modOrchestrator.translateAndPack(
        profileDirectory: profileDirectory,
        selectedEntries: selected,
        targetLanguageId: plan.targetLanguageId,
        targetLanguageDisplayName: plan.targetLanguageDisplayName,
        settings: settings,
        apiKey: apiKey,
        sessionId: sessionId,
        cancellationToken: cancellationToken,
        onSingleFileProgress: onSingleFileProgress,
        onOverallProgress: (progress) =>
            onCategoryProgress?.call(category, progress),
        onChunkResult: onChunkResult,
        onItemStarted: onItemStarted,
        packFormat: packFormat.packFormat,
      );
      summaryItems.addAll(result.summary.items);

      return _buildCategoryOutcome(
        category: category,
        translatedIds: result.translationResult.translatedJarRelativePaths,
        skippedIds: result.translationResult.skippedJarRelativePaths,
        summary: result.summary,
        outputLocations: [
          if (result.packDirectory != null) result.packDirectory!.path,
        ],
        backupLocation: result.backupDirectory?.path,
      );
    } catch (e) {
      // カテゴリ単位で例外を捕捉し、後続カテゴリの処理を継続する(§10、AC-12)。
      return InstanceTranslationCategoryOutcome(
        category: category,
        failedIds: [for (final entry in selected) entry.jarRelativePath],
        error: e,
      );
    }
  }

  Future<InstanceTranslationCategoryOutcome> _runQuests({
    required InstanceTranslationPlan plan,
    required Directory profileDirectory,
    required AppSettings settings,
    required String apiKey,
    required String sessionId,
    required CancellationToken? cancellationToken,
    required List<TranslationSummaryItem> summaryItems,
    required CategoryStartedCallback? onCategoryStarted,
    required CategoryProgressCallback? onCategoryProgress,
    required SingleFileProgressCallback? onSingleFileProgress,
    required ItemChunkResultCallback? onChunkResult,
    required CurrentItemCallback? onItemStarted,
  }) async {
    const category = InstanceTranslationCategory.quests;
    final selected = plan.effectiveQuests;
    if (selected.isEmpty || (cancellationToken?.isCancelled ?? false)) {
      return InstanceTranslationCategoryOutcome.notExecuted(category);
    }

    onCategoryStarted?.call(category);

    try {
      final result = await _questOrchestrator.translateAndWrite(
        profileDirectory: profileDirectory,
        selectedEntries: selected,
        targetLanguageId: plan.targetLanguageId,
        targetLanguageDisplayName: plan.targetLanguageDisplayName,
        settings: settings,
        apiKey: apiKey,
        sessionId: sessionId,
        cancellationToken: cancellationToken,
        onSingleFileProgress: onSingleFileProgress,
        onOverallProgress: (progress) =>
            onCategoryProgress?.call(category, progress),
        onChunkResult: onChunkResult,
        onItemStarted: onItemStarted,
      );
      summaryItems.addAll(result.summary.items);

      return _buildCategoryOutcome(
        category: category,
        translatedIds: result.translationResult.translatedPaths,
        skippedIds: result.translationResult.skippedPaths,
        summary: result.summary,
        outputLocations: [for (final file in result.writtenFiles) file.path],
        backupLocation: result.snbtBackupDirectory?.path,
      );
    } catch (e) {
      return InstanceTranslationCategoryOutcome(
        category: category,
        failedIds: [for (final entry in selected) entry.relativePath],
        error: e,
      );
    }
  }

  Future<InstanceTranslationCategoryOutcome> _runGuidebooks({
    required InstanceTranslationPlan plan,
    required Directory profileDirectory,
    required AppSettings settings,
    required String apiKey,
    required String sessionId,
    required CancellationToken? cancellationToken,
    required List<TranslationSummaryItem> summaryItems,
    required CategoryStartedCallback? onCategoryStarted,
    required CategoryProgressCallback? onCategoryProgress,
    required SingleFileProgressCallback? onSingleFileProgress,
    required ItemChunkResultCallback? onChunkResult,
    required CurrentItemCallback? onItemStarted,
  }) async {
    const category = InstanceTranslationCategory.guidebooks;
    final selected = plan.effectiveGuidebooks;
    if (selected.isEmpty || (cancellationToken?.isCancelled ?? false)) {
      return InstanceTranslationCategoryOutcome.notExecuted(category);
    }

    onCategoryStarted?.call(category);

    try {
      final result = await _patchouliOrchestrator.translateAndWrite(
        profileDirectory: profileDirectory,
        selectedEntries: selected,
        targetLanguageId: plan.targetLanguageId,
        targetLanguageDisplayName: plan.targetLanguageDisplayName,
        settings: settings,
        apiKey: apiKey,
        sessionId: sessionId,
        cancellationToken: cancellationToken,
        onSingleFileProgress: onSingleFileProgress,
        onOverallProgress: (progress) =>
            onCategoryProgress?.call(category, progress),
        onChunkResult: onChunkResult,
        onItemStarted: onItemStarted,
      );
      summaryItems.addAll(result.summary.items);

      return _buildCategoryOutcome(
        category: category,
        translatedIds: result.translationResult.translatedBookKeys,
        skippedIds: result.translationResult.skippedBookKeys,
        summary: result.summary,
        outputLocations: result.updatedJarRelativePaths,
        backupLocation: result.backupDirectory?.path,
      );
    } catch (e) {
      return InstanceTranslationCategoryOutcome(
        category: category,
        failedIds: [for (final entry in selected) entry.bookKey],
        error: e,
      );
    }
  }

  /// カテゴリの結果を、既存オーケストレーターの返り値から組み立てる(§10)。
  ///
  /// 「成功」は出力へ反映された対象、「失敗」はリトライ上限超過などで反映され
  /// なかった対象、「スキップ」は翻訳モードにより対象外となった対象。
  /// キャンセルにより未着手のまま終わった対象は、この実行に関する結果がまだ
  /// 無いため、いずれにも数えない(既存サマリの方針と同じ)。
  InstanceTranslationCategoryOutcome _buildCategoryOutcome({
    required InstanceTranslationCategory category,
    required List<String> translatedIds,
    required List<String> skippedIds,
    required TranslationSummary summary,
    required List<String> outputLocations,
    required String? backupLocation,
  }) {
    final successById = {
      for (final item in summary.items) item.id: item.success,
    };

    final successIds = <String>[];
    final failedIds = <String>[];
    for (final id in translatedIds) {
      // サマリに現れない対象は出力へ反映されていない(失敗扱い)。
      if (successById[id] ?? false) {
        successIds.add(id);
      } else {
        failedIds.add(id);
      }
    }

    return InstanceTranslationCategoryOutcome(
      category: category,
      successIds: successIds,
      failedIds: failedIds,
      skippedIds: skippedIds,
      outputLocations: outputLocations,
      backupLocation: backupLocation,
    );
  }
}
