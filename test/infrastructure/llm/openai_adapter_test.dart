import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:villager_translator/domain/llm/llm_adapter_config.dart';
import 'package:villager_translator/domain/llm/llm_api_exception.dart';
import 'package:villager_translator/domain/llm/llm_provider.dart';
import 'package:villager_translator/domain/llm/thinking_level.dart';
import 'package:villager_translator/infrastructure/llm/openai_adapter.dart';

void main() {
  const config = LlmAdapterConfig(
    apiKey: 'test-key',
    model: 'gpt-4o-mini',
    temperature: 0.5,
    maxRetries: 3,
  );

  test('provider は openai を返す', () {
    final adapter = OpenAiAdapter(
      config,
      client: MockClient((_) async => http.Response('{}', 200)),
    );
    expect(adapter.provider, LlmProvider.openai);
  });

  test('translate は chat/completions へ正しいリクエストを送信し応答を解析する', () async {
    Uri? capturedUri;
    Map<String, dynamic>? capturedBody;
    String? capturedAuth;

    final client = MockClient((request) async {
      capturedUri = request.url;
      capturedBody = jsonDecode(request.body) as Map<String, dynamic>;
      capturedAuth = request.headers['Authorization'];
      return http.Response(
        jsonEncode({
          'choices': [
            {
              'message': {'content': 'greeting: こんにちは'},
            },
          ],
        }),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });

    final adapter = OpenAiAdapter(config, client: client);
    final result = await adapter.translate(
      content: {'greeting': 'Hello'},
      targetLanguage: '日本語',
    );

    expect(
      capturedUri.toString(),
      'https://api.openai.com/v1/chat/completions',
    );
    expect(capturedAuth, 'Bearer test-key');
    expect(capturedBody!['model'], 'gpt-4o-mini');
    expect(capturedBody!['temperature'], 0.5);
    expect(result, {'greeting': 'こんにちは'});
  });

  test('401 応答は LlmApiException(statusCode: 401) を投げる', () async {
    final client = MockClient((_) async => http.Response('{}', 401));
    final adapter = OpenAiAdapter(config, client: client);

    expect(
      () => adapter.translate(content: {'a': 'Hello'}, targetLanguage: 'ja'),
      throwsA(
        isA<LlmApiException>().having((e) => e.statusCode, 'statusCode', 401),
      ),
    );
  });

  test('429 応答は retry-after を反映した LlmApiException を投げる', () async {
    final client = MockClient(
      (_) async => http.Response('{}', 429, headers: {'retry-after': '5'}),
    );
    final adapter = OpenAiAdapter(config, client: client);

    expect(
      () => adapter.translate(content: {'a': 'Hello'}, targetLanguage: 'ja'),
      throwsA(
        isA<LlmApiException>()
            .having((e) => e.statusCode, 'statusCode', 429)
            .having(
              (e) => e.retryAfter,
              'retryAfter',
              const Duration(seconds: 5),
            ),
      ),
    );
  });

  test('validateApiKey は models エンドポイントへ1回だけ GET する', () async {
    var callCount = 0;
    final client = MockClient((request) async {
      callCount++;
      expect(request.method, 'GET');
      expect(request.url.toString(), 'https://api.openai.com/v1/models');
      expect(request.headers['Authorization'], 'Bearer candidate-key');
      return http.Response('{}', 200);
    });

    final adapter = OpenAiAdapter(config, client: client);
    final isValid = await adapter.validateApiKey('candidate-key');

    expect(isValid, isTrue);
    expect(callCount, 1);
  });

  test('validateApiKey は失敗ステータスで false を返す', () async {
    final client = MockClient((_) async => http.Response('{}', 401));
    final adapter = OpenAiAdapter(config, client: client);

    expect(await adapter.validateApiKey('bad-key'), isFalse);
  });

  test('thinkingLevel が off の場合 reasoning_effort を送信しない', () async {
    Map<String, dynamic>? capturedBody;
    final client = MockClient((request) async {
      capturedBody = jsonDecode(request.body) as Map<String, dynamic>;
      return http.Response(
        jsonEncode({
          'choices': [
            {
              'message': {'content': 'greeting: こんにちは'},
            },
          ],
        }),
        200,
      );
    });

    final adapter = OpenAiAdapter(config, client: client);
    await adapter.translate(content: {'greeting': 'Hello'}, targetLanguage: 'ja');

    expect(capturedBody!.containsKey('reasoning_effort'), isFalse);
  });

  test('thinkingLevel が high の場合 reasoning_effort: "high" を送信する', () async {
    Map<String, dynamic>? capturedBody;
    final client = MockClient((request) async {
      capturedBody = jsonDecode(request.body) as Map<String, dynamic>;
      return http.Response(
        jsonEncode({
          'choices': [
            {
              'message': {'content': 'greeting: こんにちは'},
            },
          ],
        }),
        200,
      );
    });

    final adapter = OpenAiAdapter(
      const LlmAdapterConfig(
        apiKey: 'test-key',
        model: 'gpt-4o-mini',
        temperature: 0.5,
        maxRetries: 3,
        thinkingLevel: ThinkingLevel.high,
      ),
      client: client,
    );
    await adapter.translate(content: {'greeting': 'Hello'}, targetLanguage: 'ja');

    expect(capturedBody!['reasoning_effort'], 'high');
  });
}
