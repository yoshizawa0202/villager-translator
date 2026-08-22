import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:villager_translator/domain/llm/llm_adapter_config.dart';
import 'package:villager_translator/domain/llm/llm_api_exception.dart';
import 'package:villager_translator/domain/llm/llm_provider.dart';
import 'package:villager_translator/domain/llm/model_catalog.dart';
import 'package:villager_translator/domain/llm/thinking_level.dart';
import 'package:villager_translator/infrastructure/llm/deepseek_adapter.dart';

void main() {
  LlmAdapterConfig configFor(ThinkingLevel level) => LlmAdapterConfig(
    apiKey: 'test-key',
    model: 'deepseek-v4-flash',
    temperature: 0.5,
    maxRetries: 3,
    thinkingLevel: level,
    capabilities: capabilitiesFor(LlmProvider.deepseek, 'deepseek-v4-flash'),
  );

  /// 応答を固定し、送信されたリクエストを捕捉するクライアント。
  ({http.Client client, List<Map<String, dynamic>> bodies, List<Uri> uris})
  recordingClient({String content = 'greeting: こんにちは'}) {
    final bodies = <Map<String, dynamic>>[];
    final uris = <Uri>[];
    final client = MockClient((request) async {
      uris.add(request.url);
      bodies.add(jsonDecode(request.body) as Map<String, dynamic>);
      return http.Response(
        jsonEncode({
          'choices': [
            {
              'message': {
                'content': content,
                'reasoning_content': 'greeting: 内部推論のテキスト',
              },
            },
          ],
        }),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });
    return (client: client, bodies: bodies, uris: uris);
  }

  test('provider は deepseek を返す', () {
    final adapter = DeepSeekAdapter(
      configFor(ThinkingLevel.off),
      client: MockClient((_) async => http.Response('{}', 200)),
    );
    expect(adapter.provider, LlmProvider.deepseek);
  });

  test('translate は DeepSeek の chat/completions へ送信する (010 AC-13)', () async {
    final recorded = recordingClient();
    final adapter = DeepSeekAdapter(
      configFor(ThinkingLevel.off),
      client: recorded.client,
    );

    final result = await adapter.translate(
      content: {'greeting': 'Hello'},
      targetLanguage: '日本語',
    );

    expect(
      recorded.uris.single.toString(),
      'https://api.deepseek.com/v1/chat/completions',
    );
    expect(recorded.bodies.single['model'], 'deepseek-v4-flash');
    expect(result, {'greeting': 'こんにちは'});
  });

  test('temperature を送信する (010 AC-08)', () async {
    final recorded = recordingClient();
    final adapter = DeepSeekAdapter(
      configFor(ThinkingLevel.off),
      client: recorded.client,
    );

    await adapter.translate(
      content: {'greeting': 'Hello'},
      targetLanguage: 'ja',
    );

    expect(recorded.bodies.single['temperature'], 0.5);
  });

  test('思考量 off では reasoning_effort を送信しない', () async {
    final recorded = recordingClient();
    final adapter = DeepSeekAdapter(
      configFor(ThinkingLevel.off),
      client: recorded.client,
    );

    await adapter.translate(
      content: {'greeting': 'Hello'},
      targetLanguage: 'ja',
    );

    expect(recorded.bodies.single.containsKey('reasoning_effort'), isFalse);
  });

  test('思考量マッピング: high は high、max は max (010 §5.1)', () async {
    for (final entry in {
      ThinkingLevel.high: 'high',
      ThinkingLevel.max: 'max',
    }.entries) {
      final recorded = recordingClient();
      final adapter = DeepSeekAdapter(
        configFor(entry.key),
        client: recorded.client,
      );

      await adapter.translate(
        content: {'greeting': 'Hello'},
        targetLanguage: 'ja',
      );

      expect(recorded.bodies.single['reasoning_effort'], entry.value);
    }
  });

  test('カスタムモデル経由の low は low、medium は high へ補正する (010 AC-08)', () async {
    for (final entry in {
      ThinkingLevel.low: 'low',
      ThinkingLevel.medium: 'high',
    }.entries) {
      final recorded = recordingClient();
      final adapter = DeepSeekAdapter(
        configFor(entry.key),
        client: recorded.client,
      );

      await adapter.translate(
        content: {'greeting': 'Hello'},
        targetLanguage: 'ja',
      );

      expect(recorded.bodies.single['reasoning_effort'], entry.value);
    }
  });

  test('翻訳結果に reasoning_content を取り込まない (010 AC-14)', () async {
    final recorded = recordingClient();
    final adapter = DeepSeekAdapter(
      configFor(ThinkingLevel.high),
      client: recorded.client,
    );

    final result = await adapter.translate(
      content: {'greeting': 'Hello'},
      targetLanguage: 'ja',
    );

    expect(result, {'greeting': 'こんにちは'});
    expect(result['greeting']!.contains('内部推論'), isFalse);
  });

  test('validateApiKey は models へ1回だけ GET する', () async {
    var callCount = 0;
    final client = MockClient((request) async {
      callCount++;
      expect(request.method, 'GET');
      expect(request.url.toString(), 'https://api.deepseek.com/v1/models');
      expect(request.headers['Authorization'], 'Bearer candidate-key');
      return http.Response('{}', 200);
    });

    final adapter = DeepSeekAdapter(
      configFor(ThinkingLevel.off),
      client: client,
    );

    expect(await adapter.validateApiKey('candidate-key'), isTrue);
    expect(callCount, 1);
  });

  test('401 応答は日本語メッセージの LlmApiException を投げる', () {
    final adapter = DeepSeekAdapter(
      configFor(ThinkingLevel.off),
      client: MockClient((_) async => http.Response('{"error":"x"}', 401)),
    );

    expect(
      () => adapter.translate(content: {'a': 'Hello'}, targetLanguage: 'ja'),
      throwsA(
        isA<LlmApiException>()
            .having((e) => e.statusCode, 'statusCode', 401)
            .having((e) => e.message, 'message', contains('APIキー')),
      ),
    );
  });
}
