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

/// 1チャンクを [maxRetries] 回まで(既定3回)リトライしながら翻訳する
/// (feature-spec.md §5.3)。
///
/// 401/403 相当の認証エラーはリトライせず即座に例外を再送出する。
/// それ以外のエラーはリトライ回数を使い切るまで [waiter] で待機して再試行し、
/// 使い切った場合は最後の例外を再送出する(スキップ判断は呼び出し側で行う)。
Future<Map<String, String>> translateChunkWithRetry(
  Map<String, String> chunk, {
  required ChunkTranslator translateChunk,
  int maxRetries = 3,
  RetryWaiter waiter = _defaultWaiter,
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
      await waiter(resolveRetryWait(error, attempt));
    }
  }
}

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
Future<List<Map<String, String>>> translateChunksWithPartialSuccess(
  List<Map<String, String>> chunks, {
  required ChunkTranslator translateChunk,
  int maxRetries = 3,
  RetryWaiter waiter = _defaultWaiter,
  CancellationToken? cancellationToken,
  void Function(int completedChunks, int totalChunks)? onChunkComplete,
}) async {
  final results = <Map<String, String>>[];

  for (var i = 0; i < chunks.length; i++) {
    if (cancellationToken?.isCancelled ?? false) {
      break;
    }

    try {
      final translated = await translateChunkWithRetry(
        chunks[i],
        translateChunk: translateChunk,
        maxRetries: maxRetries,
        waiter: waiter,
      );
      results.add(translated);
    } catch (error) {
      if (isAuthError(error)) {
        rethrow;
      }
      // リトライ使い切り: このチャンクはスキップして次のチャンクへ進む。
    }

    onChunkComplete?.call(i + 1, chunks.length);
  }

  return results;
}
