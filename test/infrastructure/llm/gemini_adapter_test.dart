import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:villager_translator/domain/llm/llm_adapter_config.dart';
import 'package:villager_translator/domain/llm/llm_provider.dart';
import 'package:villager_translator/domain/llm/thinking_level.dart';
import 'package:villager_translator/infrastructure/llm/gemini_adapter.dart';

void main() {
  const config = LlmAdapterConfig(
    apiKey: 'test-key',
    model: 'gemini-1.5-flash',
    temperature: 0.5,
    maxRetries: 3,
  );

  test('provider は gemini を返す(google ではない)', () {
    final adapter = GeminiAdapter(
      config,
      client: MockClient((_) async => http.Response('{}', 200)),
    );
    expect(adapter.provider, LlmProvider.gemini);
    expect(adapter.provider.id, 'gemini');
  });

  test('translate は generateContent へ送信し応答を解析する', () async {
    Uri? capturedUri;
    Map<String, dynamic>? capturedBody;

    final client = MockClient((request) async {
      capturedUri = request.url;
      capturedBody = jsonDecode(request.body) as Map<String, dynamic>;
      return http.Response(
        jsonEncode({
          'candidates': [
            {
              'content': {
                'parts': [
                  {'text': 'greeting: こんにちは'},
                ],
              },
            },
          ],
        }),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });

    final adapter = GeminiAdapter(config, client: client);
    final result = await adapter.translate(
      content: {'greeting': 'Hello'},
      targetLanguage: '日本語',
    );

    expect(
      capturedUri.toString(),
      'https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent?key=test-key',
    );
    expect(capturedBody!['generationConfig']['temperature'], 0.5);
    expect(result, {'greeting': 'こんにちは'});
  });

  test('validateApiKey は models 一覧エンドポイントへ1回だけ GET する', () async {
    var callCount = 0;
    final client = MockClient((request) async {
      callCount++;
      expect(request.method, 'GET');
      expect(request.url.toString(), contains('key=candidate-key'));
      return http.Response('{}', 200);
    });

    final adapter = GeminiAdapter(config, client: client);
    expect(await adapter.validateApiKey('candidate-key'), isTrue);
    expect(callCount, 1);
  });

  test('thinkingLevel が off の場合 thinkingConfig を送信しない', () async {
    Map<String, dynamic>? capturedBody;
    final client = MockClient((request) async {
      capturedBody = jsonDecode(request.body) as Map<String, dynamic>;
      return http.Response(
        jsonEncode({
          'candidates': [
            {
              'content': {
                'parts': [
                  {'text': 'greeting: こんにちは'},
                ],
              },
            },
          ],
        }),
        200,
      );
    });

    final adapter = GeminiAdapter(config, client: client);
    await adapter.translate(content: {'greeting': 'Hello'}, targetLanguage: 'ja');

    expect(
      (capturedBody!['generationConfig'] as Map<String, dynamic>).containsKey(
        'thinkingConfig',
      ),
      isFalse,
    );
  });

  test('thinkingLevel が high の場合 thinkingConfig.thinkingBudget を送信する', () async {
    Map<String, dynamic>? capturedBody;
    final client = MockClient((request) async {
      capturedBody = jsonDecode(request.body) as Map<String, dynamic>;
      return http.Response(
        jsonEncode({
          'candidates': [
            {
              'content': {
                'parts': [
                  {'text': 'greeting: こんにちは'},
                ],
              },
            },
          ],
        }),
        200,
      );
    });

    final adapter = GeminiAdapter(
      const LlmAdapterConfig(
        apiKey: 'test-key',
        model: 'gemini-1.5-flash',
        temperature: 0.5,
        maxRetries: 3,
        thinkingLevel: ThinkingLevel.high,
      ),
      client: client,
    );
    await adapter.translate(content: {'greeting': 'Hello'}, targetLanguage: 'ja');

    final generationConfig =
        capturedBody!['generationConfig'] as Map<String, dynamic>;
    final thinkingConfig =
        generationConfig['thinkingConfig'] as Map<String, dynamic>;
    expect(thinkingConfig['thinkingBudget'], 24576);
  });
}
