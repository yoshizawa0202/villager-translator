import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:villager_translator/domain/llm/llm_adapter_config.dart';
import 'package:villager_translator/domain/llm/llm_provider.dart';
import 'package:villager_translator/domain/llm/model_catalog.dart';
import 'package:villager_translator/domain/llm/thinking_level.dart';
import 'package:villager_translator/infrastructure/llm/kimi_adapter.dart';

void main() {
  LlmAdapterConfig configFor(ThinkingLevel level) => LlmAdapterConfig(
    apiKey: 'test-key',
    model: 'kimi-k3',
    temperature: 0.5,
    maxRetries: 3,
    thinkingLevel: level,
    capabilities: capabilitiesFor(LlmProvider.kimi, 'kimi-k3'),
  );

  ({http.Client client, List<Map<String, dynamic>> bodies, List<Uri> uris})
  recordingClient() {
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
                'content': 'greeting: こんにちは',
                'reasoning_content': 'greeting: 内部推論',
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

  test('provider は kimi を返す', () {
    final adapter = KimiAdapter(
      configFor(ThinkingLevel.max),
      client: MockClient((_) async => http.Response('{}', 200)),
    );
    expect(adapter.provider, LlmProvider.kimi);
  });

  test('translate は Kimi の chat/completions へ送信する', () async {
    final recorded = recordingClient();
    final adapter = KimiAdapter(
      configFor(ThinkingLevel.max),
      client: recorded.client,
    );

    final result = await adapter.translate(
      content: {'greeting': 'Hello'},
      targetLanguage: '日本語',
    );

    expect(
      recorded.uris.single.toString(),
      'https://api.moonshot.ai/v1/chat/completions',
    );
    expect(recorded.bodies.single['model'], 'kimi-k3');
    expect(result, {'greeting': 'こんにちは'});
  });

  test('temperature を送信する (010 AC-12)', () async {
    final recorded = recordingClient();
    final adapter = KimiAdapter(
      configFor(ThinkingLevel.max),
      client: recorded.client,
    );

    await adapter.translate(
      content: {'greeting': 'Hello'},
      targetLanguage: 'ja',
    );

    expect(recorded.bodies.single['temperature'], 0.5);
  });

  test('思考量マッピング: 低/高/最大 (010 AC-12)', () async {
    for (final entry in {
      ThinkingLevel.low: 'low',
      ThinkingLevel.high: 'high',
      ThinkingLevel.max: 'max',
    }.entries) {
      final recorded = recordingClient();
      final adapter = KimiAdapter(
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
    final adapter = KimiAdapter(
      configFor(ThinkingLevel.max),
      client: recorded.client,
    );

    final result = await adapter.translate(
      content: {'greeting': 'Hello'},
      targetLanguage: 'ja',
    );

    expect(result, {'greeting': 'こんにちは'});
  });

  test('validateApiKey は models へ1回だけ GET する', () async {
    var callCount = 0;
    final client = MockClient((request) async {
      callCount++;
      expect(request.method, 'GET');
      expect(request.url.toString(), 'https://api.moonshot.ai/v1/models');
      expect(request.headers['Authorization'], 'Bearer candidate-key');
      return http.Response('{}', 200);
    });

    final adapter = KimiAdapter(configFor(ThinkingLevel.max), client: client);

    expect(await adapter.validateApiKey('candidate-key'), isTrue);
    expect(callCount, 1);
  });
}
