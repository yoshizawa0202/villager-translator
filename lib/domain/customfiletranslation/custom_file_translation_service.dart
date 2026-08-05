import '../common/cancellation_token.dart';
import '../common/translation_progress.dart';
import '../translation/retry_policy.dart';
import 'custom_file_scan_entry.dart';

Future<void> _defaultWaiter(Duration duration) =>
    Future<void>.delayed(duration);

/// 翻訳が完了したカスタムファイル1件分の出力。
class CustomFileTranslationOutput {
  const CustomFileTranslationOutput({
    required this.entry,
    required this.entries,
  });

  final CustomFileScanEntry entry;

  /// 翻訳結果のキー→値([entry.sourceEntries] と同じキー集合)。
  final Map<String, String> entries;
}

/// [translateCustomFileEntries] の結果。
class CustomFileTranslationResult {
  const CustomFileTranslationResult({
    required this.outputs,
    required this.translatedPaths,
    required this.skippedPaths,
  });

  final List<CustomFileTranslationOutput> outputs;
  final List<String> translatedPaths;
  final List<String> skippedPaths;
}

/// 選択されたカスタムファイルを翻訳する(feature-spec.md §9)。
///
/// 「既存翻訳をスキップ」判定を持たないため、選択された全件が常に翻訳対象と
/// なる(受け入れ条件2)。ファイル全体を1つの翻訳単位として LLM アダプターへ
/// 渡し、チャンク分割は行わない(移行上の判断)。
Future<CustomFileTranslationResult> translateCustomFileEntries({
  required List<CustomFileScanEntry> selectedEntries,
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

  final outputs = <CustomFileTranslationOutput>[];
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

    final translatedChunks = await translateChunksWithPartialSuccess(
      [entry.sourceEntries],
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

    translatedPaths.add(entry.relativePath);
    outputs.add(
      CustomFileTranslationOutput(entry: entry, entries: newlyTranslated),
    );
    reportOverallProgress();
  }

  return CustomFileTranslationResult(
    outputs: outputs,
    translatedPaths: translatedPaths,
    skippedPaths: skippedPaths,
  );
}
