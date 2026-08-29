import 'dart:io';

import 'package:villager_translator/domain/common/cancellation_token.dart';
import 'package:villager_translator/domain/common/translation_progress.dart';
import 'package:villager_translator/domain/common/translation_summary.dart';
import 'package:villager_translator/domain/modtranslation/resource_pack_builder.dart';
import 'package:villager_translator/domain/settings/app_settings.dart';
import 'package:villager_translator/infrastructure/modtranslation/mod_translation_orchestrator.dart';
import 'package:villager_translator/infrastructure/patchoulitranslation/patchouli_translation_orchestrator.dart';
import 'package:villager_translator/infrastructure/questtranslation/quest_translation_orchestrator.dart';

/// 既存オーケストレーターへの 1 回分の呼び出し記録(012 のテスト方針)。
class OrchestratorCall {
  OrchestratorCall({
    required this.category,
    required this.sessionId,
    required this.settings,
    required this.cancellationToken,
    required this.itemCount,
    this.packFormat,
  });

  final String category;
  final String sessionId;
  final AppSettings settings;
  final CancellationToken? cancellationToken;
  final int itemCount;
  final int? packFormat;
}

/// 既存 3 オーケストレーターの呼び出しを記録する差し替え用の実装。
class OrchestratorRecorder {
  final List<OrchestratorCall> calls = [];
}

TranslationSummary _summary(
  String sessionId,
  List<TranslationSummaryItem> items,
) => TranslationSummary(
  sessionId: sessionId,
  targetLanguage: 'ja_jp',
  createdAt: DateTime(2026, 8, 24),
  items: items,
);

TranslationSummaryItem summaryItem({
  required TranslationTargetType type,
  required String id,
  bool success = true,
}) => TranslationSummaryItem(
  type: type,
  id: id,
  displayName: id,
  targetLanguage: 'ja_jp',
  outputPath: success ? id : null,
  success: success,
  translatedKeyCount: success ? 1 : 0,
  totalKeyCount: 1,
);

class RecordingModOrchestrator extends ModTranslationOrchestrator {
  RecordingModOrchestrator(
    this.recorder, {
    this.translatedPaths = const [],
    this.skippedPaths = const [],
    this.failedPaths = const [],
    this.error,
    this.onCall,
  });

  final OrchestratorRecorder recorder;
  final List<String> translatedPaths;
  final List<String> skippedPaths;
  final List<String> failedPaths;
  final Object? error;
  final void Function()? onCall;

  @override
  Future<ModTranslateAndPackResult> translateAndPack({
    required Directory profileDirectory,
    required List<ModScanEntry> selectedEntries,
    required String targetLanguageId,
    required String targetLanguageDisplayName,
    required AppSettings settings,
    required String apiKey,
    required String sessionId,
    CancellationToken? cancellationToken,
    SingleFileProgressCallback? onSingleFileProgress,
    OverallProgressCallback? onOverallProgress,
    ItemChunkResultCallback? onChunkResult,
    CurrentItemCallback? onItemStarted,
    int packFormat = kResourcePackFormat,
  }) async {
    recorder.calls.add(
      OrchestratorCall(
        category: 'mods',
        sessionId: sessionId,
        settings: settings,
        cancellationToken: cancellationToken,
        itemCount: selectedEntries.length,
        packFormat: packFormat,
      ),
    );
    onCall?.call();
    if (error != null) throw error!;

    onOverallProgress?.call(
      OverallProgress(
        completedItems: translatedPaths.length,
        totalItems: selectedEntries.length,
      ),
    );

    ModTranslationTarget targetFor(String jarRelativePath) {
      final entry = selectedEntries.firstWhere(
        (entry) => entry.jarRelativePath == jarRelativePath,
      );
      return ModTranslationTarget(
        jarRelativePath: jarRelativePath,
        modId: entry.modInfo.id,
      );
    }

    return ModTranslateAndPackResult(
      translationResult: ModTranslationResult(
        outputs: const [],
        translatedTargets: [
          for (final path in [...translatedPaths, ...failedPaths])
            targetFor(path),
        ],
        skippedTargets: [for (final path in skippedPaths) targetFor(path)],
      ),
      packDirectory: Directory('${profileDirectory.path}/resourcepacks/pack'),
      backupDirectory: null,
      summary: _summary(sessionId, [
        for (final path in translatedPaths)
          summaryItem(type: TranslationTargetType.mod, id: path),
        for (final path in failedPaths)
          summaryItem(
            type: TranslationTargetType.mod,
            id: path,
            success: false,
          ),
      ]),
    );
  }
}

class RecordingQuestOrchestrator extends QuestTranslationOrchestrator {
  RecordingQuestOrchestrator(
    this.recorder, {
    this.translatedPaths = const [],
    this.skippedPaths = const [],
    this.failedPaths = const [],
    this.error,
  });

  final OrchestratorRecorder recorder;
  final List<String> translatedPaths;
  final List<String> skippedPaths;
  final List<String> failedPaths;
  final Object? error;

  @override
  Future<QuestTranslateAndWriteResult> translateAndWrite({
    required Directory profileDirectory,
    required List<QuestScanEntry> selectedEntries,
    required String targetLanguageId,
    required String targetLanguageDisplayName,
    required AppSettings settings,
    required String apiKey,
    required String sessionId,
    CancellationToken? cancellationToken,
    SingleFileProgressCallback? onSingleFileProgress,
    OverallProgressCallback? onOverallProgress,
    ItemChunkResultCallback? onChunkResult,
    CurrentItemCallback? onItemStarted,
  }) async {
    recorder.calls.add(
      OrchestratorCall(
        category: 'quests',
        sessionId: sessionId,
        settings: settings,
        cancellationToken: cancellationToken,
        itemCount: selectedEntries.length,
      ),
    );
    if (error != null) throw error!;

    onOverallProgress?.call(
      OverallProgress(
        completedItems: translatedPaths.length,
        totalItems: selectedEntries.length,
      ),
    );

    return QuestTranslateAndWriteResult(
      translationResult: QuestTranslationResult(
        outputs: const [],
        translatedPaths: [...translatedPaths, ...failedPaths],
        skippedPaths: skippedPaths,
      ),
      writtenFiles: const [],
      snbtBackupDirectory: null,
      summary: _summary(sessionId, [
        for (final path in translatedPaths)
          summaryItem(type: TranslationTargetType.quest, id: path),
        for (final path in failedPaths)
          summaryItem(
            type: TranslationTargetType.quest,
            id: path,
            success: false,
          ),
      ]),
    );
  }
}

class RecordingPatchouliOrchestrator extends PatchouliTranslationOrchestrator {
  RecordingPatchouliOrchestrator(
    this.recorder, {
    this.translatedBookKeys = const [],
    this.skippedBookKeys = const [],
    this.failedBookKeys = const [],
    this.error,
  });

  final OrchestratorRecorder recorder;
  final List<String> translatedBookKeys;
  final List<String> skippedBookKeys;
  final List<String> failedBookKeys;
  final Object? error;

  @override
  Future<PatchouliTranslateAndWriteResult> translateAndWrite({
    required Directory profileDirectory,
    required List<PatchouliBookEntry> selectedEntries,
    required String targetLanguageId,
    required String targetLanguageDisplayName,
    required AppSettings settings,
    required String apiKey,
    required String sessionId,
    CancellationToken? cancellationToken,
    SingleFileProgressCallback? onSingleFileProgress,
    OverallProgressCallback? onOverallProgress,
    ItemChunkResultCallback? onChunkResult,
    CurrentItemCallback? onItemStarted,
  }) async {
    recorder.calls.add(
      OrchestratorCall(
        category: 'guidebooks',
        sessionId: sessionId,
        settings: settings,
        cancellationToken: cancellationToken,
        itemCount: selectedEntries.length,
      ),
    );
    if (error != null) throw error!;

    onOverallProgress?.call(
      OverallProgress(
        completedItems: translatedBookKeys.length,
        totalItems: selectedEntries.length,
      ),
    );

    return PatchouliTranslateAndWriteResult(
      translationResult: PatchouliTranslationResult(
        outputs: const [],
        translatedBookKeys: [...translatedBookKeys, ...failedBookKeys],
        skippedBookKeys: skippedBookKeys,
      ),
      updatedJarRelativePaths: const [],
      backupDirectory: null,
      summary: _summary(sessionId, [
        for (final key in translatedBookKeys)
          summaryItem(type: TranslationTargetType.patchouli, id: key),
        for (final key in failedBookKeys)
          summaryItem(
            type: TranslationTargetType.patchouli,
            id: key,
            success: false,
          ),
      ]),
    );
  }
}
