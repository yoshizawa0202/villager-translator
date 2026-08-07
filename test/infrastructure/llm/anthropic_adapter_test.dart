import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:villager_translator/domain/llm/llm_adapter_config.dart';
import 'package:villager_translator/domain/llm/llm_provider.dart';
import 'package:villager_translator/domain/llm/thinking_level.dart';
import 'package:villager_translator/infrastructure/llm/anthropic_adapter.dart';

void main() {
  const config = LlmAdapterConfig(
    apiKey: 'test-key',
    model: 'claude-3-5-haiku-20241022',
    temperature: 0.5,
    maxRetries: 3,
  );

  test('provider は anthropic を返す', () {
    final adapter = AnthropicAdapter(
      config,
      client: MockClient((_) async => http.Response('{}', 200)),
    );
    expect(adapter.provider, LlmProvider.anthropic);
  });

  test('translate は messages へ x-api-key ヘッダー付きで送信し応答を解析する', () async {
    Uri? capturedUri;
    Map<String, dynamic>? capturedBody;
    String? capturedApiKeyHeader;
    String? capturedVersionHeader;

    final client = MockClient((request) async {
      capturedUri = request.url;
      capturedBody = jsonDecode(request.body) as Map<String, dynamic>;
      capturedApiKeyHeader = request.headers['x-api-key'];
      capturedVersionHeader = request.headers['anthropic-version'];
      return http.Response(
        jsonEncode({
          'content': [
            {'type': 'text', 'text': 'greeting: こんにちは'},
          ],
        }),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });

    final adapter = AnthropicAdapter(config, client: client);
    final result = await adapter.translate(
      content: {'greeting': 'Hello'},
      targetLanguage: '日本語',
    );

    expect(capturedUri.toString(), 'https://api.anthropic.com/v1/messages');
    expect(capturedApiKeyHeader, 'test-key');
    expect(capturedVersionHeader, isNotNull);
    expect(capturedBody!['model'], 'claude-3-5-haiku-20241022');
    expect(capturedBody!['system'], isNotEmpty);
    expect(result, {'greeting': 'こんにちは'});
  });

  test('validateApiKey は models エンドポイントへ1回だけ GET する', () async {
    var callCount = 0;
    final client = MockClient((request) async {
      callCount++;
      expect(request.method, 'GET');
      expect(request.headers['x-api-key'], 'candidate-key');
      return http.Response('{}', 200);
    });

    final adapter = AnthropicAdapter(config, client: client);
    expect(await adapter.validateApiKey('candidate-key'), isTrue);
    expect(callCount, 1);
  });

  test('thinkingLevel が off の場合 thinking フィールドを送信しない', () async {
    Map<String, dynamic>? capturedBody;
    final client = MockClient((request) async {
      capturedBody = jsonDecode(request.body) as Map<String, dynamic>;
      return http.Response(
        jsonEncode({
          'content': [
            {'type': 'text', 'text': 'greeting: こんにちは'},
          ],
        }),
        200,
      );
    });

    final adapter = AnthropicAdapter(config, client: client);
    await adapter.translate(content: {'greeting': 'Hello'}, targetLanguage: 'ja');

    expect(capturedBody!.containsKey('thinking'), isFalse);
  });

  test('thinkingLevel が high の場合 thinking.budget_tokens を max_tokens 未満で送信する', () async {
    Map<String, dynamic>? capturedBody;
    final client = MockClient((request) async {
      capturedBody = jsonDecode(request.body) as Map<String, dynamic>;
      return http.Response(
        jsonEncode({
          'content': [
            {'type': 'text', 'text': 'greeting: こんにちは'},
          ],
        }),
        200,
      );
    });

    final adapter = AnthropicAdapter(
      const LlmAdapterConfig(
        apiKey: 'test-key',
        model: 'claude-3-5-haiku-20241022',
        temperature: 0.5,
        maxRetries: 3,
        thinkingLevel: ThinkingLevel.high,
      ),
      client: client,
    );
    await adapter.translate(content: {'greeting': 'Hello'}, targetLanguage: 'ja');

    final thinking = capturedBody!['thinking'] as Map<String, dynamic>;
    expect(thinking['type'], 'enabled');
    expect(thinking['budget_tokens'], lessThan(AnthropicAdapter.maxOutputTokens));
  });
}
