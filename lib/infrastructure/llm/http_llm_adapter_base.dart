import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../domain/llm/llm_api_exception.dart';

/// 3つの実プロバイダーアダプター(OpenAI/Anthropic/Gemini)が共有する
/// HTTP 呼び出しの下回り。
///
/// チャンク分割・リトライは `docs/specs/003-translation-engine.md` の責務のため、
/// ここでは [LlmApiException] を投げるところまでを行う(1回の呼び出しのみ)。
abstract class HttpLlmAdapterBase {
  HttpLlmAdapterBase({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  /// テスト・上位実装から HTTP クライアントへアクセスするための保護メンバー。
  http.Client get httpClient => _client;

  /// JSON ボディを POST し、成功時はデコード済みの JSON を返す。
  /// 401 相当は認証エラー、429 相当はレート制限として [LlmApiException] に
  /// 変換する。
  Future<dynamic> postJson(
    Uri uri, {
    required Map<String, String> headers,
    required Map<String, dynamic> body,
  }) async {
    final response = await _client.post(
      uri,
      headers: {'Content-Type': 'application/json', ...headers},
      body: jsonEncode(body),
    );
    return _decodeOrThrow(response);
  }

  /// 疎通確認用の軽量な GET リクエスト。成功(2xx)なら true を返す。
  Future<bool> getOk(Uri uri, {required Map<String, String> headers}) async {
    final response = await _client.get(uri, headers: headers);
    return response.statusCode >= 200 && response.statusCode < 300;
  }

  dynamic _decodeOrThrow(http.Response response) {
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return jsonDecode(response.body);
    }

    if (response.statusCode == 401 || response.statusCode == 403) {
      throw LlmApiException(
        statusCode: response.statusCode,
        message: 'APIキーが無効か、認証に失敗しました',
      );
    }

    if (response.statusCode == 429) {
      throw LlmApiException(
        statusCode: response.statusCode,
        message: 'レート制限に達しました',
        retryAfter: _parseRetryAfter(response.headers['retry-after']),
      );
    }

    throw LlmApiException(
      statusCode: response.statusCode,
      message: 'LLM API 呼び出しに失敗しました (status: ${response.statusCode})',
    );
  }

  Duration? _parseRetryAfter(String? headerValue) {
    if (headerValue == null) return null;
    final seconds = int.tryParse(headerValue.trim());
    if (seconds == null) return null;
    return Duration(seconds: seconds);
  }
}
