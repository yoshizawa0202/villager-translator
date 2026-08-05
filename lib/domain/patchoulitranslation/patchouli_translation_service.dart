import '../common/cancellation_token.dart';
import '../common/translation_progress.dart';
import '../settings/existing_translation_policy.dart';
import '../translation/diff_update.dart';
import '../translation/retry_policy.dart';
import 'patchouli_book_entry.dart';
import 'patchouli_scanner.dart';

/// [entry] の対象言語ミラーファイル群から実際に読み込んだ既存翻訳の状態
/// (feature-spec.md §8.1)。
class PatchouliExistingTranslation {
  const PatchouliExistingTranslation({
    required this.isComplete,
    required this.entries,
  });

  /// `en_us/` の全ファイル分のミラーファイルが JAR 内に揃っているか
  /// (受け入れ条件5)。「スキップ」判定はこのフラグでのみ行う。
  final bool isComplete;

  /// 実際に読み込めたミラーファイルから抽出した既存エントリ(複合キー→値)。
  /// 一部のミラーファイルしか存在しない場合は、読み込めた分のみを含む
  /// (「差分更新」で既存エントリの値を保護するために使う)。
  final Map<String, String> entries;
}

/// [entry] の対象言語ミラーファイル群を読み込む関数(「既存翻訳の扱い」の
/// 翻訳直前の実チェック)。
typedef ExistingPatchouliEntriesLoader =
    Future<PatchouliExistingTranslation> Function(PatchouliBookEntry entry);

Future<void> _defaultWaiter(Duration duration) =>
    Future<void>.delayed(duration);

/// 翻訳が完了した本1冊分の出力(JAR へ書き出す内容)。
class PatchouliTranslationOutput {
  const PatchouliTranslationOutput({
    required this.entry,
    required this.entries,
  });

  final PatchouliBookEntry entry;

  /// 書き出す全内容(複合キー `{ファイル相対パス}#{抽出順連番}` → 値、
  /// 既存内容とのマージ済み)。
  final Map<String, String> entries;
}

/// [translatePatchouliBooks] の結果。
class PatchouliTranslationResult {
  const PatchouliTranslationResult({
    required this.outputs,
    required this.translatedBookKeys,
    required this.skippedBookKeys,
  });

  /// JAR へ書き出す本ごとの出力(スキップされた本は含まない)。
  final List<PatchouliTranslationOutput> outputs;

  /// 翻訳(または差分更新)が実施された本(`{modId}:{bookId}`)の一覧。
  final List<String> translatedBookKeys;

  /// スキップされた本の一覧。
  final List<String> skippedBookKeys;

  bool get hasOutputs => outputs.isNotEmpty;
}

/// 選択された本を、既存翻訳の扱い([policy])に従って翻訳する
/// (feature-spec.md §8.1、§8.2)。
///
/// 処理順序は `{modId}:{bookId}` のアルファベット順に固定する。
/// - **スキップ**: `en_us/` 全ファイル分のミラーファイルが揃っている
///   (受け入れ条件5)場合のみスキップする。
/// - **差分更新**: `003` の差分更新ロジックで、複合キー(ファイル相対パス+
///   キー位置)単位の不足分のみを翻訳し、既存エントリの値は変更しない
///   (受け入れ条件6)。
/// - **全て再翻訳**: 既存の有無に関わらず常に全キーを翻訳し直す。
///
/// 同一本に属する全ファイルの抽出結果は1つの翻訳単位として扱い、チャンク
/// 分割は行わない(feature-spec.md §8.1、受け入れ条件4)。
Future<PatchouliTranslationResult> translatePatchouliBooks({
  required List<PatchouliBookEntry> selectedEntries,
  required ExistingTranslationPolicy policy,
  required ExistingPatchouliEntriesLoader loadExistingTargetEntries,
  required ChunkTranslator translateChunk,
  int maxRetries = 3,
  RetryWaiter waiter = _defaultWaiter,
  CancellationToken? cancellationToken,
  SingleFileProgressCallback? onSingleFileProgress,
  OverallProgressCallback? onOverallProgress,
  ItemChunkResultCallback? onChunkResult,
}) async {
  final orderedEntries = sortPatchouliBookEntries(selectedEntries);

  final outputs = <PatchouliTranslationOutput>[];
  final translatedBookKeys = <String>[];
  final skippedBookKeys = <String>[];
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
      skippedBookKeys.add(entry.bookKey);
      reportOverallProgress();
      continue;
    }

    final Map<String, String> keysToTranslate;
    final Map<String, String> baseExisting;

    if (policy == ExistingTranslationPolicy.skip) {
      final existing = await loadExistingTargetEntries(entry);
      if (existing.isComplete) {
        skippedBookKeys.add(entry.bookKey);
        reportOverallProgress();
        continue;
      }
      keysToTranslate = entry.sourceEntries;
      baseExisting = const {};
    } else if (policy == ExistingTranslationPolicy.diffUpdate) {
      final existing = await loadExistingTargetEntries(entry);
      final job = resolveDiffUpdateJob(
        sourceEntries: entry.sourceEntries,
        existingTargetEntries: existing.entries,
      );
      if (job.isSkipped) {
        skippedBookKeys.add(entry.bookKey);
        reportOverallProgress();
        continue;
      }
      keysToTranslate = job.keysToTranslate;
      baseExisting = job.existingEntries;
    } else {
      keysToTranslate = entry.sourceEntries;
      baseExisting = const {};
    }

    // 本全体を1つの翻訳単位とするため、チャンク分割せず単一チャンクとして送る。
    final translatedChunks = await translateChunksWithPartialSuccess(
      [keysToTranslate],
      translateChunk: translateChunk,
      maxRetries: maxRetries,
      waiter: waiter,
      cancellationToken: cancellationToken,
      onChunkComplete: (completed, total) => onSingleFileProgress?.call(
        ChunkProgress(completedChunks: completed, totalChunks: total),
      ),
      onChunkResult: (result) => onChunkResult?.call(entry.bookKey, result),
    );

    final newlyTranslated = <String, String>{};
    for (final chunk in translatedChunks) {
      newlyTranslated.addAll(chunk);
    }

    if (newlyTranslated.isEmpty) {
      // 唯一のチャンクがリトライを使い切った(=この本全体が失敗)。
      skippedBookKeys.add(entry.bookKey);
      reportOverallProgress();
      continue;
    }

    final finalEntries = policy == ExistingTranslationPolicy.diffUpdate
        ? mergeDiffUpdateResult(
            existingEntries: baseExisting,
            newlyTranslatedEntries: newlyTranslated,
          )
        : <String, String>{...baseExisting, ...newlyTranslated};

    translatedBookKeys.add(entry.bookKey);
    outputs.add(
      PatchouliTranslationOutput(entry: entry, entries: finalEntries),
    );
    reportOverallProgress();
  }

  return PatchouliTranslationResult(
    outputs: outputs,
    translatedBookKeys: translatedBookKeys,
    skippedBookKeys: skippedBookKeys,
  );
}
