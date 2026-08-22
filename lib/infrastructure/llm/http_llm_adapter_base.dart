import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../domain/llm/llm_api_exception.dart';

/// 実プロバイダーアダプターが共有する HTTP 呼び出しの下回り。
///
/// チャンク分割・リトライは `docs/specs/003-translation-engine.md` の責務のため、
/// ここでは [LlmApiException] を投げるところまでを行う(1回の呼び出しのみ)。
///
/// 認証失敗・レート制限・サーバー障害・タイムアウトの表示をここへ集約し、
/// 個別アダプターが応答本文や秘密情報を誤って表示するリスクを無くす
/// (`docs/specs/010-additional-llm-providers.md` §11、§14.6)。
/// [LlmApiException.message] には API キー・Authorization ヘッダー・HTTP 応答
/// 本文・プロバイダーの内部情報を一切含めない(010 AC-17)。
abstract class HttpLlmAdapterBase {
  HttpLlmAdapterBase({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  /// HTTP 通信のタイムアウト(010 §11)。
  static const Duration requestTimeout = Duration(minutes: 3);

  /// テスト・上位実装から HTTP クライアントへアクセスするための保護メンバー。
  http.Client get httpClient => _client;

  /// JSON ボディを POST し、成功時はデコード済みの JSON を返す。
  /// HTTP エラーとタイムアウトは利用者向けの日本語メッセージを持つ
  /// [LlmApiException] へ変換する。
  Future<dynamic> postJson(
    Uri uri, {
    required Map<String, String> headers,
    required Map<String, dynamic> body,
  }) async {
    final response = await _withTimeout(
      () => _client.post(
        uri,
        headers: {'Content-Type': 'application/json', ...headers},
        body: jsonEncode(body),
      ),
    );
    return _decodeOrThrow(response);
  }

  /// 疎通確認用の軽量な GET リクエスト。成功(2xx)なら true を返す。
  ///
  /// HTTP エラーは「疎通できなかった」ことを表す false として扱い、
  /// タイムアウト・ネットワーク障害のみ [LlmApiException] を投げる。
  Future<bool> getOk(Uri uri, {required Map<String, String> headers}) async {
    final response = await _withTimeout(
      () => _client.get(uri, headers: headers),
    );
    return response.statusCode >= 200 && response.statusCode < 300;
  }

  Future<http.Response> _withTimeout(Future<http.Response> Function() send) {
    return send().timeout(
      requestTimeout,
      onTimeout: () => throw LlmApiException(
        message:
            '通信がタイムアウトしました(${requestTimeout.inMinutes}分)。'
            'ネットワーク接続とプロバイダーの状態を確認してください',
      ),
    );
  }

  dynamic _decodeOrThrow(http.Response response) {
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return jsonDecode(response.body);
    }
    throw _exceptionFor(response);
  }

  /// HTTP ステータスコードを利用者向けの日本語メッセージへ変換する(010 §11)。
  LlmApiException _exceptionFor(http.Response response) {
    final status = response.statusCode;

    if (status == 401) {
      return LlmApiException(
        statusCode: status,
        message: 'APIキーが無効か、認証に失敗しました。設定画面の API キーを確認してください',
      );
    }
    if (status == 403) {
      return LlmApiException(
        statusCode: status,
        message: 'この API キーでは要求した操作が許可されていません。プランと権限を確認してください',
      );
    }
    if (status == 404) {
      return LlmApiException(
        statusCode: status,
        message: '指定したモデルまたはエンドポイントが見つかりません。モデル名とベース URL を確認してください',
      );
    }
    if (status == 429) {
      return LlmApiException(
        statusCode: status,
        message: 'レート制限に達しました。しばらく待ってから再試行してください',
        retryAfter: _parseRetryAfter(response.headers['retry-after']),
      );
    }
    if (status >= 500 && status <= 599) {
      return LlmApiException(
        statusCode: status,
        message: 'プロバイダー側で一時的な障害が発生しています。しばらく待ってから再試行してください',
      );
    }

    return LlmApiException(
      statusCode: status,
      message: 'LLM API 呼び出しに失敗しました (status: $status)',
    );
  }

  Duration? _parseRetryAfter(String? headerValue) {
    if (headerValue == null) return null;
    final seconds = int.tryParse(headerValue.trim());
    if (seconds == null) return null;
    return Duration(seconds: seconds);
  }
}
