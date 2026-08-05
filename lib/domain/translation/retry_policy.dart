import '../common/cancellation_token.dart';
import '../llm/llm_api_exception.dart';

/// チャンク1件を翻訳する関数(通常は `LlmAdapter.translate` の呼び出しを包む)。
typedef ChunkTranslator =
    Future<Map<String, String>> Function(Map<String, String> chunk);

/// リトライ待機を行う関数。テストでは実待機を避けるため差し替える。
typedef RetryWaiter = Future<void> Function(Duration duration);

Future<void> _defaultWaiter(Duration duration) =>
    Future<void>.delayed(duration);

/// 401/403 相当の認証エラーかどうかを判定する(feature-spec.md §5.3)。
bool isAuthError(Object error) =>
    error is LlmApiException &&
    (error.statusCode == 401 || error.statusCode == 403);

/// リトライ前に待機すべき時間を算出する。
///
/// 429 相当のレート制限で `retry-after` が判明している場合はそれを尊重し、
/// それ以外の一時的な失敗(タイムアウト・5xx 相当)は試行回数に応じた
/// 線形バックオフ([attempt] 秒)を用いる。
Duration resolveRetryWait(Object error, int attempt) {
  if (error is LlmApiException && error.retryAfter != null) {
    return error.retryAfter!;
  }
  return Duration(seconds: attempt);
}

/// 失敗した試行のたびに呼ばれる観測用コールバック(リトライ前に発火)。
typedef ChunkRetryObserver = void Function(int attempt, Object error);

/// 1チャンクを [maxRetries] 回まで(既定3回)リトライしながら翻訳する
/// (feature-spec.md §5.3)。
///
/// 401/403 相当の認証エラーはリトライせず即座に例外を再送出する。
/// それ以外のエラーはリトライ回数を使い切るまで [waiter] で待機して再試行し、
/// 使い切った場合は最後の例外を再送出する(スキップ判断は呼び出し側で行う)。
/// 失敗するたびに(リトライ前に) [onRetry] を呼び、試行回数とエラーを通知する。
Future<Map<String, String>> translateChunkWithRetry(
  Map<String, String> chunk, {
  required ChunkTranslator translateChunk,
  int maxRetries = 3,
  RetryWaiter waiter = _defaultWaiter,
  ChunkRetryObserver? onRetry,
}) async {
  var attempt = 0;
  while (true) {
    try {
      return await translateChunk(chunk);
    } catch (error) {
      if (isAuthError(error)) {
        rethrow;
      }
      attempt++;
      if (attempt > maxRetries) {
        rethrow;
      }
      onRetry?.call(attempt, error);
      await waiter(resolveRetryWait(error, attempt));
    }
  }
}

/// チャンク1件分の最終処理結果(Issue#10: 粒度の細かいデバッグログ用)。
///
/// [chunkIndex] は0始まり。[retryCount] はリトライが発生した回数(0なら
/// 初回の試行で成功)。[success] が `false` の場合、[error] にリトライを
/// 使い切った際の最後の例外が入る。
class ChunkResult {
  const ChunkResult({
    required this.chunkIndex,
    required this.totalChunks,
    required this.keyCount,
    required this.success,
    required this.retryCount,
    this.error,
  });

  final int chunkIndex;
  final int totalChunks;
  final int keyCount;
  final bool success;
  final int retryCount;
  final Object? error;
}

/// [ChunkResult] の通知コールバック。
typedef ChunkResultCallback = void Function(ChunkResult result);

/// 複数チャンクを順に翻訳する。リトライを使い切ったチャンクはスキップし、
/// 他のチャンクの処理を継続する(部分成功、feature-spec.md §5.3)。
///
/// 401/403 相当の認証エラーが発生した場合は、以降のチャンクも同じ理由で
/// 失敗し続けるだけであるため、バッチ全体を中断して例外を再送出する。
///
/// [cancellationToken] がキャンセル済みの場合、次のチャンクを開始せずに
/// その時点までの結果を返す(実行中のチャンクは中断しない、feature-spec.md
/// §10、008-progress-log-history.md 受け入れ条件5)。[onChunkComplete] は
/// 各チャンクの処理後(成功・失敗を問わず)に完了数/総数を通知する。
/// [onChunkResult] は各チャンクの最終結果(成功/失敗・リトライ回数・エラー)を
/// 通知する(Issue#10: 粒度の細かいデバッグログ用)。
Future<List<Map<String, String>>> translateChunksWithPartialSuccess(
  List<Map<String, String>> chunks, {
  required ChunkTranslator translateChunk,
  int maxRetries = 3,
  RetryWaiter waiter = _defaultWaiter,
  CancellationToken? cancellationToken,
  void Function(int completedChunks, int totalChunks)? onChunkComplete,
  ChunkResultCallback? onChunkResult,
}) async {
  final results = <Map<String, String>>[];

  for (var i = 0; i < chunks.length; i++) {
    if (cancellationToken?.isCancelled ?? false) {
      break;
    }

    var retryCount = 0;
    try {
      final translated = await translateChunkWithRetry(
        chunks[i],
        translateChunk: translateChunk,
        maxRetries: maxRetries,
        waiter: waiter,
        onRetry: (attempt, error) => retryCount = attempt,
      );
      results.add(translated);
      onChunkResult?.call(
        ChunkResult(
          chunkIndex: i,
          totalChunks: chunks.length,
          keyCount: chunks[i].length,
          success: true,
          retryCount: retryCount,
        ),
      );
    } catch (error) {
      if (isAuthError(error)) {
        rethrow;
      }
      // リトライ使い切り: このチャンクはスキップして次のチャンクへ進む。
      onChunkResult?.call(
        ChunkResult(
          chunkIndex: i,
          totalChunks: chunks.length,
          keyCount: chunks[i].length,
          success: false,
          retryCount: retryCount,
          error: error,
        ),
      );
    }

    onChunkComplete?.call(i + 1, chunks.length);
  }

  return results;
}
