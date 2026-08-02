/// LLM プロバイダーへの API 呼び出しが失敗したことを表す例外。
///
/// [message] に API キーなど機密情報を含めてはならない
/// (feature-spec.md §15: API キーをログや例外メッセージに出力しない)。
/// `docs/specs/003-translation-engine.md` のリトライロジックが
/// [statusCode] や [retryAfter] を参照して再試行の可否・待機時間を判断する。
class LlmApiException implements Exception {
  const LlmApiException({
    required this.message,
    this.statusCode,
    this.retryAfter,
  });

  /// HTTP ステータスコード(取得できない場合は null)。
  final int? statusCode;

  /// API キーを含まないエラーメッセージ。
  final String message;

  /// レート制限時の `retry-after` から算出した待機時間。
  final Duration? retryAfter;

  @override
  String toString() =>
      'LlmApiException(statusCode: $statusCode, message: $message)';
}
