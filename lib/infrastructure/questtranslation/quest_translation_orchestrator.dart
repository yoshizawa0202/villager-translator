import 'dart:io';

import 'package:path/path.dart' as p;

import '../../domain/common/cancellation_token.dart';
import '../../domain/common/translation_progress.dart';
import '../../domain/common/translation_summary.dart';
import '../../domain/llm/llm_adapter_config.dart';
import '../../domain/questtranslation/quest_output_builder.dart';
import '../../domain/questtranslation/quest_scan_entry.dart';
import '../../domain/questtranslation/quest_translation_service.dart';
import '../../domain/settings/app_settings.dart';
import '../../domain/translation/lang_codec.dart';
import '../common/translation_summary_writer.dart';
import '../llm/llm_adapter_factory.dart';
import 'quest_backup_writer.dart';
import 'quest_directory_scanner.dart';
import 'quest_output_writer.dart';

export '../../domain/questtranslation/quest_scan_entry.dart';
export '../../domain/questtranslation/quest_translation_service.dart';

/// [QuestTranslationOrchestrator.translateAndWrite] の結果。
class QuestTranslateAndWriteResult {
  const QuestTranslateAndWriteResult({
    required this.translationResult,
    required this.writtenFiles,
    required this.snbtBackupDirectory,
    required this.summary,
  });

  final QuestTranslationResult translationResult;
  final List<File> writtenFiles;

  /// SNBT を1件でも選択した場合のバックアップ先(選択がなければ `null`)。
  final Directory? snbtBackupDirectory;

  /// この実行の翻訳履歴サマリ(`translation_summary.json` の内容と同一)。
  final TranslationSummary summary;
}

/// クエスト(FTB Quests / Better Quests)のスキャン・翻訳・出力・バックアップを
/// 統括する(feature-spec.md §7)。
class QuestTranslationOrchestrator {
  QuestTranslationOrchestrator({LlmAdapterFactory? adapterFactory})
    : _adapterFactory = adapterFactory ?? DefaultLlmAdapterFactory();

  final LlmAdapterFactory _adapterFactory;

  /// `{プロファイル}` 配下の FTB Quests / Better Quests をスキャンする。
  Future<List<QuestScanEntry>> scan({required Directory profileDirectory}) {
    return scanQuestsDirectory(profileDirectory: profileDirectory);
  }

  /// 選択されたクエストファイルを翻訳し、出力先へ書き出す。
  ///
  /// SNBT が選択に含まれる場合、翻訳(上書き)前に必ずバックアップする
  /// (feature-spec.md §7.1、受け入れ条件6)。
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
    final snbtEntries = selectedEntries
        .where((e) => e.format == QuestFormat.ftbQuestsSnbt)
        .toList();

    Directory? backupDirectory;
    if (snbtEntries.isNotEmpty) {
      backupDirectory = await backupSnbtOriginals(
        profileDirectory: profileDirectory,
        entries: snbtEntries,
        sessionId: sessionId,
      );
    }

    final adapter = _adapterFactory.create(
      settings.llm.provider,
      LlmAdapterConfig(
        apiKey: apiKey,
        model: settings.llm.effectiveModel,
        temperature: settings.llm.temperature,
        maxRetries: settings.llm.maxRetries,
      ),
    );

    Future<Map<String, String>> translateChunk(Map<String, String> chunk) {
      return adapter.translate(
        content: chunk,
        targetLanguage: targetLanguageDisplayName,
        systemPrompt: settings.llm.systemPrompt,
        userPromptTemplate: settings.llm.userPrompt,
      );
    }

    Future<Map<String, String>?> loadExistingTargetEntries(
      QuestScanEntry entry,
    ) => _loadExistingQuestEntries(profileDirectory, entry, targetLanguageId);

    final translationResult = await translateQuestEntries(
      selectedEntries: selectedEntries,
      policy: settings.translation.existingTranslationPolicy,
      loadExistingTargetEntries: loadExistingTargetEntries,
      translateChunk: translateChunk,
      maxRetries: settings.llm.maxRetries,
      cancellationToken: cancellationToken,
      onSingleFileProgress: onSingleFileProgress,
      onOverallProgress: onOverallProgress,
      onChunkResult: onChunkResult,
      onItemStarted: onItemStarted,
    );

    final writtenFiles = <File>[];
    for (final output in translationResult.outputs) {
      final files = buildQuestOutputFiles(output, targetLanguageId);
      writtenFiles.addAll(
        await writeQuestOutputFiles(
          profileDirectory: profileDirectory,
          files: files,
        ),
      );
    }

    final summary = _buildSummary(
      sessionId: sessionId,
      targetLanguageId: targetLanguageId,
      selectedEntries: selectedEntries,
      translationResult: translationResult,
    );
    await const TranslationSummaryWriter().write(
      profileDirectory: profileDirectory,
      summary: summary,
    );

    return QuestTranslateAndWriteResult(
      translationResult: translationResult,
      writtenFiles: writtenFiles,
      snbtBackupDirectory: backupDirectory,
      summary: summary,
    );
  }
}

/// 選択されたクエストファイルと処理結果を突き合わせ、翻訳履歴サマリの項目一覧を
/// 組み立てる。キャンセルにより未着手のまま終わったファイルはサマリに含めない。
TranslationSummary _buildSummary({
  required String sessionId,
  required String targetLanguageId,
  required List<QuestScanEntry> selectedEntries,
  required QuestTranslationResult translationResult,
}) {
  final entriesByPath = {for (final e in selectedEntries) e.relativePath: e};
  final outputsByPath = {
    for (final o in translationResult.outputs) o.entry.relativePath: o,
  };

  final items = <TranslationSummaryItem>[];

  for (final path in translationResult.translatedPaths) {
    final entry = entriesByPath[path];
    final output = outputsByPath[path];
    if (entry == null || output == null) continue;

    final totalKeyCount = entry.sourceEntries.length;
    final translatedKeyCount = output.entries.keys
        .where(entry.sourceEntries.containsKey)
        .length;

    items.add(
      TranslationSummaryItem(
        type: TranslationTargetType.quest,
        id: path,
        displayName: path,
        targetLanguage: targetLanguageId,
        outputPath: path,
        success: totalKeyCount == 0 || translatedKeyCount >= totalKeyCount,
        translatedKeyCount: translatedKeyCount,
        totalKeyCount: totalKeyCount,
      ),
    );
  }

  for (final path in translationResult.skippedPaths) {
    final entry = entriesByPath[path];
    if (entry == null) continue;

    final keyCount = entry.sourceEntries.length;
    items.add(
      TranslationSummaryItem(
        type: TranslationTargetType.quest,
        id: path,
        displayName: path,
        targetLanguage: targetLanguageId,
        outputPath: null,
        success: true,
        translatedKeyCount: keyCount,
        totalKeyCount: keyCount,
      ),
    );
  }

  return TranslationSummary(
    sessionId: sessionId,
    targetLanguage: targetLanguageId,
    createdAt: DateTime.now(),
    items: items,
  );
}

Future<Map<String, String>?> _loadExistingQuestEntries(
  Directory profileDirectory,
  QuestScanEntry entry,
  String targetLanguageId,
) async {
  final path = existingTranslationCheckPath(entry, targetLanguageId);
  if (path == null) return null; // SNBT: 判定不能。

  final file = File(p.joinAll([profileDirectory.path, ...path.split('/')]));
  if (!await file.exists()) return null;

  try {
    final format = path.toLowerCase().endsWith('.json')
        ? LangFormat.json
        : LangFormat.lang;
    return decodeLang(await file.readAsString(), format);
  } on FormatException {
    return null;
  }
}
