import '../common/cancellation_token.dart';
import '../common/translation_progress.dart';
import '../settings/existing_translation_policy.dart';
import '../translation/diff_update.dart';
import '../translation/retry_policy.dart';
import 'quest_scan_entry.dart';

/// [entry] の対象言語ファイル(または SNBT の場合は判定不能)が既に存在すれば、
/// その内容を返す(存在しない、または SNBT で判定不能な場合は `null`)。
typedef ExistingQuestEntriesLoader =
    Future<Map<String, String>?> Function(QuestScanEntry entry);

Future<void> _defaultWaiter(Duration duration) =>
    Future<void>.delayed(duration);

/// 翻訳が完了したクエストファイル1件分の出力。
class QuestTranslationOutput {
  const QuestTranslationOutput({required this.entry, required this.entries});

  final QuestScanEntry entry;

  /// 書き出す全内容(JSON/LANG: 既存内容とのマージ済み。SNBT: 抽出順連番キー
  /// → 翻訳結果、[entry.snbtSpans] を使った再構成に使う)。
  final Map<String, String> entries;
}

/// [translateQuestEntries] の結果。
class QuestTranslationResult {
  const QuestTranslationResult({
    required this.outputs,
    required this.translatedPaths,
    required this.skippedPaths,
  });

  final List<QuestTranslationOutput> outputs;
  final List<String> translatedPaths;
  final List<String> skippedPaths;
}

/// 選択されたクエストファイルを、既存翻訳の扱い([policy])に従って翻訳する
/// (feature-spec.md §7.3)。
///
/// - SNBT は既存翻訳の判定が不能なため、[policy] の値に関わらず常に
///   「全て再翻訳」として扱う(受け入れ条件11)。
/// - JSON/LANG(KubeJS lang、Better Quests 標準/直接)は `003` の差分更新
///   ロジックをそのまま適用する(受け入れ条件10)。
/// - ファイル全体を1つの翻訳単位として LLM アダプターへ渡す(チャンク分割は
///   行わない、受け入れ条件12)。
Future<QuestTranslationResult> translateQuestEntries({
  required List<QuestScanEntry> selectedEntries,
  required ExistingTranslationPolicy policy,
  required ExistingQuestEntriesLoader loadExistingTargetEntries,
  required ChunkTranslator translateChunk,
  int maxRetries = 3,
  RetryWaiter waiter = _defaultWaiter,
  CancellationToken? cancellationToken,
  SingleFileProgressCallback? onSingleFileProgress,
  OverallProgressCallback? onOverallProgress,
  ItemChunkResultCallback? onChunkResult,
}) async {
  final orderedEntries = selectedEntries.toList()
    ..sort((a, b) => a.relativePath.compareTo(b.relativePath));

  final outputs = <QuestTranslationOutput>[];
  final translatedPaths = <String>[];
  final skippedPaths = <String>[];
  var processedCount = 0;

  void reportOverallProgress() {
    processedCount++;
    onOverallProgress?.call(
      OverallProgress(
        completedItems: processedCount,
        totalItems: orderedEntries.length,
      ),
    );
  }

  for (final entry in orderedEntries) {
    if (cancellationToken?.isCancelled ?? false) {
      break;
    }

    if (entry.sourceEntries.isEmpty) {
      skippedPaths.add(entry.relativePath);
      reportOverallProgress();
      continue;
    }

    final isSnbt = entry.format == QuestFormat.ftbQuestsSnbt;
    final effectivePolicy = isSnbt
        ? ExistingTranslationPolicy.retranslateAll
        : policy;
    final existing = isSnbt ? null : await loadExistingTargetEntries(entry);

    final Map<String, String> keysToTranslate;
    final Map<String, String> baseExisting;

    if (effectivePolicy == ExistingTranslationPolicy.skip) {
      if (existing != null) {
        skippedPaths.add(entry.relativePath);
        reportOverallProgress();
        continue;
      }
      keysToTranslate = entry.sourceEntries;
      baseExisting = const {};
    } else if (effectivePolicy == ExistingTranslationPolicy.diffUpdate) {
      final job = resolveDiffUpdateJob(
        sourceEntries: entry.sourceEntries,
        existingTargetEntries: existing,
      );
      if (job.isSkipped) {
        skippedPaths.add(entry.relativePath);
        reportOverallProgress();
        continue;
      }
      keysToTranslate = job.keysToTranslate;
      baseExisting = job.existingEntries;
    } else {
      keysToTranslate = entry.sourceEntries;
      baseExisting = const {};
    }

    // ファイル全体を1つの翻訳単位とするため、チャンク分割せず単一チャンクとして送る。
    final translatedChunks = await translateChunksWithPartialSuccess(
      [keysToTranslate],
      translateChunk: translateChunk,
      maxRetries: maxRetries,
      waiter: waiter,
      cancellationToken: cancellationToken,
      onChunkComplete: (completed, total) => onSingleFileProgress?.call(
        ChunkProgress(completedChunks: completed, totalChunks: total),
      ),
      onChunkResult: (result) =>
          onChunkResult?.call(entry.relativePath, result),
    );

    final newlyTranslated = <String, String>{};
    for (final chunk in translatedChunks) {
      newlyTranslated.addAll(chunk);
    }

    if (newlyTranslated.isEmpty) {
      // 唯一のチャンクがリトライを使い切った(=このファイル全体が失敗)。
      skippedPaths.add(entry.relativePath);
      reportOverallProgress();
      continue;
    }

    final finalEntries = effectivePolicy == ExistingTranslationPolicy.diffUpdate
        ? mergeDiffUpdateResult(
            existingEntries: baseExisting,
            newlyTranslatedEntries: newlyTranslated,
          )
        : <String, String>{...baseExisting, ...newlyTranslated};

    translatedPaths.add(entry.relativePath);
    outputs.add(QuestTranslationOutput(entry: entry, entries: finalEntries));
    reportOverallProgress();
  }

  return QuestTranslationResult(
    outputs: outputs,
    translatedPaths: translatedPaths,
    skippedPaths: skippedPaths,
  );
}
