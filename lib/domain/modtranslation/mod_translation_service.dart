import '../common/cancellation_token.dart';
import '../common/translation_progress.dart';
import '../settings/existing_translation_policy.dart';
import '../translation/diff_update.dart';
import '../translation/lang_codec.dart';
import '../translation/retry_policy.dart';
import 'mod_scan_entry.dart';
import 'mod_scanner.dart';

/// [entries] をチャンクへ分割する関数。エントリ数ベース/トークンベースいずれの
/// 分割方式を使うかは呼び出し側([003-translation-engine.md] の chunker.dart)が
/// 決定して注入する。
typedef ChunkEntries =
    List<Map<String, String>> Function(Map<String, String> entries);

/// [entry] の対象言語ファイルが JAR 内に既に存在すれば、その内容を返す
/// (存在しなければ `null`)。差分更新・スキップ判定の「翻訳直前の実チェック」
/// (feature-spec.md §4.2)として使う。
typedef ExistingTargetEntriesLoader =
    Future<Map<String, String>?> Function(ModScanEntry entry);

Future<void> _defaultWaiter(Duration duration) =>
    Future<void>.delayed(duration);

/// 翻訳処理中の MOD 1件を一意に参照する情報。
///
/// MOD ID はリソースパックの名前空間であり、同じ ID の JAR が複数存在し得る。
/// 入力・結果・再試行の突き合わせには [jarRelativePath] を使う。
class ModTranslationTarget {
  const ModTranslationTarget({
    required this.jarRelativePath,
    required this.modId,
  });

  factory ModTranslationTarget.fromEntry(ModScanEntry entry) =>
      ModTranslationTarget(
        jarRelativePath: entry.jarRelativePath,
        modId: entry.modInfo.id,
      );

  final String jarRelativePath;
  final String modId;
}

/// 翻訳が完了した MOD 1件分の出力(リソースパックへ書き出す内容)。
class ModTranslationOutput {
  const ModTranslationOutput({
    required this.jarRelativePath,
    required this.modId,
    required this.format,
    required this.entries,
  });

  /// この出力の入力元を一意に識別する `mods/` からの相対パス。
  final String jarRelativePath;
  final String modId;
  final LangFormat format;

  /// 書き出す全キー(既存内容とのマージ済み、キー未ソート)。
  final Map<String, String> entries;
}

/// [translateSelectedMods] の結果。
class ModTranslationResult {
  const ModTranslationResult({
    required this.outputs,
    required this.translatedTargets,
    required this.skippedTargets,
  });

  /// リソースパックへ書き出す MOD ごとの出力(スキップされた MOD は含まない)。
  final List<ModTranslationOutput> outputs;

  /// 翻訳(または差分更新)を実施した対象。チャンク失敗を含む。
  final List<ModTranslationTarget> translatedTargets;

  /// 既存翻訳方針によりスキップされた対象。
  final List<ModTranslationTarget> skippedTargets;

  /// UI 表示との後方互換用。内部の突き合わせには使用しない。
  List<String> get translatedModIds =>
      translatedTargets.map((target) => target.modId).toList();

  /// UI 表示との後方互換用。内部の突き合わせには使用しない。
  List<String> get skippedModIds =>
      skippedTargets.map((target) => target.modId).toList();

  List<String> get translatedJarRelativePaths =>
      translatedTargets.map((target) => target.jarRelativePath).toList();

  List<String> get skippedJarRelativePaths =>
      skippedTargets.map((target) => target.jarRelativePath).toList();

  /// リソースパックを作成すべきかどうか(受け入れ条件11)。
  bool get hasOutputs => outputs.isNotEmpty;
}

/// 選択された MOD を、既存翻訳の扱い([policy])に従って翻訳する
/// (feature-spec.md §6.2)。
///
/// 処理順序は MOD ID、同一 ID 内では JAR 相対パスのアルファベット順に
/// 固定する(受け入れ条件7)。
/// - **スキップ**: 翻訳直前に対象言語ファイルの存在を再確認し、存在すれば
///   スキップ件数としてカウントする(受け入れ条件8)。
/// - **差分更新**: `003` の差分更新ロジックで不足キーのみを翻訳し、
///   既存キーの値は変更しない(受け入れ条件9)。
/// - **全て再翻訳**: 既存の有無に関わらず常に全キーを翻訳する(受け入れ条件10)。
Future<ModTranslationResult> translateSelectedMods({
  required List<ModScanEntry> selectedEntries,
  required ExistingTranslationPolicy policy,
  required ExistingTargetEntriesLoader loadExistingTargetEntries,
  required ChunkEntries chunkEntries,
  required ChunkTranslator translateChunk,
  int maxRetries = 3,
  RetryWaiter waiter = _defaultWaiter,
  CancellationToken? cancellationToken,
  SingleFileProgressCallback? onSingleFileProgress,
  OverallProgressCallback? onOverallProgress,
  ItemChunkResultCallback? onChunkResult,
  CurrentItemCallback? onItemStarted,
}) async {
  final orderedEntries = sortModEntriesById(selectedEntries);

  final outputs = <ModTranslationOutput>[];
  final translatedTargets = <ModTranslationTarget>[];
  final skippedTargets = <ModTranslationTarget>[];
  var processedCount = 0;

  for (final entry in orderedEntries) {
    if (cancellationToken?.isCancelled ?? false) {
      break;
    }
    onItemStarted?.call(entry.modInfo.name);

    final existing = await loadExistingTargetEntries(entry);

    final Map<String, String> keysToTranslate;
    final Map<String, String> baseExisting;

    if (policy == ExistingTranslationPolicy.skip) {
      if (existing != null) {
        skippedTargets.add(ModTranslationTarget.fromEntry(entry));
        processedCount++;
        onOverallProgress?.call(
          OverallProgress(
            completedItems: processedCount,
            totalItems: orderedEntries.length,
          ),
        );
        continue;
      }
      keysToTranslate = entry.sourceEntries;
      baseExisting = const {};
    } else if (policy == ExistingTranslationPolicy.diffUpdate) {
      final job = resolveDiffUpdateJob(
        sourceEntries: entry.sourceEntries,
        existingTargetEntries: existing,
      );
      if (job.isSkipped) {
        skippedTargets.add(ModTranslationTarget.fromEntry(entry));
        processedCount++;
        onOverallProgress?.call(
          OverallProgress(
            completedItems: processedCount,
            totalItems: orderedEntries.length,
          ),
        );
        continue;
      }
      keysToTranslate = job.keysToTranslate;
      baseExisting = job.existingEntries;
    } else {
      keysToTranslate = entry.sourceEntries;
      baseExisting = const {};
    }

    final chunks = chunkEntries(keysToTranslate);
    final translatedChunks = await translateChunksWithPartialSuccess(
      chunks,
      translateChunk: translateChunk,
      maxRetries: maxRetries,
      waiter: waiter,
      cancellationToken: cancellationToken,
      onChunkComplete: (completed, total) => onSingleFileProgress?.call(
        ChunkProgress(completedChunks: completed, totalChunks: total),
      ),
      onChunkResult: (result) =>
          onChunkResult?.call(entry.modInfo.name, result),
    );

    final newlyTranslated = <String, String>{};
    for (final chunk in translatedChunks) {
      newlyTranslated.addAll(chunk);
    }

    final finalEntries = policy == ExistingTranslationPolicy.diffUpdate
        ? mergeDiffUpdateResult(
            existingEntries: baseExisting,
            newlyTranslatedEntries: newlyTranslated,
          )
        : <String, String>{...baseExisting, ...newlyTranslated};

    translatedTargets.add(ModTranslationTarget.fromEntry(entry));
    outputs.add(
      ModTranslationOutput(
        jarRelativePath: entry.jarRelativePath,
        modId: entry.modInfo.id,
        format: entry.langFormat,
        entries: finalEntries,
      ),
    );
    processedCount++;
    onOverallProgress?.call(
      OverallProgress(
        completedItems: processedCount,
        totalItems: orderedEntries.length,
      ),
    );
  }

  return ModTranslationResult(
    outputs: outputs,
    translatedTargets: translatedTargets,
    skippedTargets: skippedTargets,
  );
}
