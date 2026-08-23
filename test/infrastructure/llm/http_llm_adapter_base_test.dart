import 'dart:async';
import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:villager_translator/domain/llm/llm_adapter_config.dart';
import 'package:villager_translator/domain/llm/llm_api_exception.dart';
import 'package:villager_translator/infrastructure/llm/http_llm_adapter_base.dart';
import 'package:villager_translator/infrastructure/llm/openai_adapter.dart';

/// エラー変換だけを検証するための最小アダプター。
class _TestAdapter extends HttpLlmAdapterBase {
  _TestAdapter({super.client});

  Future<dynamic> post() => postJson(
    Uri.parse('https://example.test/v1/chat/completions'),
    headers: const {'Authorization': 'Bearer super-secret-key'},
    body: const {'model': 'test'},
  );

  Future<bool> get() => getOk(
    Uri.parse('https://example.test/v1/models'),
    headers: const {'Authorization': 'Bearer super-secret-key'},
  );
}

void main() {
  const config = LlmAdapterConfig(
    apiKey: 'super-secret-key',
    model: 'gpt-5.6-luna',
    temperature: 0.5,
    maxRetries: 3,
  );

  Future<LlmApiException> captureError(
    int statusCode, {
    String body = '',
  }) async {
    final adapter = _TestAdapter(
      client: MockClient((_) async => http.Response(body, statusCode)),
    );
    try {
      await adapter.post();
      fail('例外が投げられなかった (status: $statusCode)');
    } on LlmApiException catch (error) {
      return error;
    }
  }

  /// 応答が永久に返らないクライアントで [action] を実行し、タイムアウト時間を
  /// 仮想時間で経過させて捕捉した例外を返す(実時間で3分待たないため)。
  LlmApiException captureTimeout(Future<void> Function() action) {
    late LlmApiException captured;
    var completed = false;

    fakeAsync((async) {
      unawaited(
        action().catchError((Object error) {
          captured = error as LlmApiException;
          completed = true;
        }),
      );
      async.elapse(
        HttpLlmAdapterBase.requestTimeout + const Duration(seconds: 1),
      );
      async.flushMicrotasks();
    });

    expect(completed, isTrue, reason: 'タイムアウトで完了しなかった');
    return captured;
  }

  group('HTTP ステータスの日本語メッセージ変換 (010 AC-17)', () {
    test('401 は認証エラーとして案内する', () async {
      final error = await captureError(401);
      expect(error.statusCode, 401);
      expect(error.message, contains('APIキー'));
    });

    test('403 は権限エラーとして案内する', () async {
      final error = await captureError(403);
      expect(error.statusCode, 403);
      expect(error.message, contains('許可されていません'));
    });

    test('404 はモデル・エンドポイントの確認を案内する', () async {
      final error = await captureError(404);
      expect(error.statusCode, 404);
      expect(error.message, contains('見つかりません'));
    });

    test('429 はレート制限として案内し retry-after を反映する', () async {
      final adapter = _TestAdapter(
        client: MockClient(
          (_) async => http.Response('', 429, headers: {'retry-after': '7'}),
        ),
      );

      await expectLater(
        adapter.post(),
        throwsA(
          isA<LlmApiException>()
              .having((e) => e.statusCode, 'statusCode', 429)
              .having((e) => e.message, 'message', contains('レート制限'))
              .having(
                (e) => e.retryAfter,
                'retryAfter',
                const Duration(seconds: 7),
              ),
        ),
      );
    });

    test('5xx はプロバイダー側の一時障害として案内する', () async {
      for (final status in [500, 502, 503, 599]) {
        final error = await captureError(status);
        expect(error.statusCode, status);
        expect(error.message, contains('一時的な障害'));
      }
    });

    test('メッセージに API キー・応答本文・認証ヘッダーを含めない (010 AC-17)', () async {
      const responseBody =
          '{"error":{"message":"invalid api key super-secret-key"}}';
      for (final status in [401, 403, 404, 429, 500, 418]) {
        final error = await captureError(status, body: responseBody);
        expect(error.message.contains('super-secret-key'), isFalse);
        expect(error.message.contains(responseBody), isFalse);
        expect(error.message.contains('invalid api key'), isFalse);
        expect(error.message.contains('Bearer'), isFalse);
        expect(error.message.contains('Authorization'), isFalse);
      }
    });

    test('2xx は JSON をデコードして返す', () async {
      final adapter = _TestAdapter(
        client: MockClient(
          (_) async => http.Response(jsonEncode({'ok': true}), 200),
        ),
      );

      expect(await adapter.post(), {'ok': true});
    });

    test('getOk は HTTP エラーを false として扱う', () async {
      final adapter = _TestAdapter(
        client: MockClient((_) async => http.Response('', 401)),
      );

      expect(await adapter.get(), isFalse);
    });
  });

  group('通信タイムアウト (010 AC-17)', () {
    test('タイムアウトは3分', () {
      expect(HttpLlmAdapterBase.requestTimeout, const Duration(minutes: 3));
    });

    test('POST がタイムアウトすると日本語メッセージの例外になる', () {
      final adapter = _TestAdapter(
        client: MockClient((_) => Completer<http.Response>().future),
      );

      final error = captureTimeout(() async {
        await adapter.post();
      });

      expect(error.statusCode, isNull);
      expect(error.message, contains('タイムアウト'));
      expect(error.message.contains('super-secret-key'), isFalse);
    });

    test('GET(疎通確認)がタイムアウトすると日本語メッセージの例外になる', () {
      final adapter = OpenAiAdapter(
        config,
        client: MockClient((_) => Completer<http.Response>().future),
      );

      final error = captureTimeout(() async {
        await adapter.validateApiKey('candidate');
      });

      expect(error.message, contains('タイムアウト'));
      expect(error.message.contains('candidate'), isFalse);
    });
  });
}
