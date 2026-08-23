import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:villager_translator/domain/llm/llm_adapter_config.dart';
import 'package:villager_translator/domain/llm/llm_provider.dart';
import 'package:villager_translator/domain/llm/model_catalog.dart';
import 'package:villager_translator/domain/llm/thinking_level.dart';
import 'package:villager_translator/infrastructure/llm/qwen_adapter.dart';

void main() {
  LlmAdapterConfig configFor(ThinkingLevel level, {String? baseUrl}) =>
      LlmAdapterConfig(
        apiKey: 'test-key',
        model: 'qwen3.8-max',
        temperature: 0.5,
        maxRetries: 3,
        thinkingLevel: level,
        baseUrl: baseUrl,
        capabilities: capabilitiesFor(LlmProvider.qwen, 'qwen3.8-max'),
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
              'message': {'content': 'greeting: こんにちは'},
            },
          ],
        }),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });
    return (client: client, bodies: bodies, uris: uris);
  }

  test('provider は qwen を返す', () {
    final adapter = QwenAdapter(
      configFor(ThinkingLevel.off),
      client: MockClient((_) async => http.Response('{}', 200)),
    );
    expect(adapter.provider, LlmProvider.qwen);
  });

  test('ベース URL 未指定なら国際向けエンドポイントを使う (010 AC-15)', () async {
    final recorded = recordingClient();
    final adapter = QwenAdapter(
      configFor(ThinkingLevel.off),
      client: recorded.client,
    );

    await adapter.translate(
      content: {'greeting': 'Hello'},
      targetLanguage: 'ja',
    );

    expect(
      recorded.uris.single.toString(),
      '${QwenAdapter.internationalBaseUrl}/chat/completions',
    );
    expect(
      QwenAdapter.internationalBaseUrl,
      'https://dashscope-intl.aliyuncs.com/compatible-mode/v1',
    );
  });

  test('ベース URL の上書きを反映する (010 AC-15)', () async {
    final recorded = recordingClient();
    final adapter = QwenAdapter(
      configFor(ThinkingLevel.off, baseUrl: 'https://example.test/v1'),
      client: recorded.client,
    );

    await adapter.translate(
      content: {'greeting': 'Hello'},
      targetLanguage: 'ja',
    );

    expect(
      recorded.uris.single.toString(),
      'https://example.test/v1/chat/completions',
    );
  });

  test('ベース URL 末尾のスラッシュを重複させない', () async {
    final recorded = recordingClient();
    final adapter = QwenAdapter(
      configFor(ThinkingLevel.off, baseUrl: 'https://example.test/v1/'),
      client: recorded.client,
    );

    await adapter.translate(
      content: {'greeting': 'Hello'},
      targetLanguage: 'ja',
    );

    expect(
      recorded.uris.single.toString(),
      'https://example.test/v1/chat/completions',
    );
  });

  test('temperature を送信する (010 AC-09)', () async {
    final recorded = recordingClient();
    final adapter = QwenAdapter(
      configFor(ThinkingLevel.off),
      client: recorded.client,
    );

    await adapter.translate(
      content: {'greeting': 'Hello'},
      targetLanguage: 'ja',
    );

    expect(recorded.bodies.single['temperature'], 0.5);
  });

  test('思考量 off/on を enable_thinking へマッピングする (010 AC-09)', () async {
    for (final entry in {
      ThinkingLevel.off: false,
      ThinkingLevel.on: true,
    }.entries) {
      final recorded = recordingClient();
      final adapter = QwenAdapter(
        configFor(entry.key),
        client: recorded.client,
      );

      await adapter.translate(
        content: {'greeting': 'Hello'},
        targetLanguage: 'ja',
      );

      expect(recorded.bodies.single['enable_thinking'], entry.value);
    }
  });

  test('翻訳結果は choices[0].message.content のみを使う (010 AC-14)', () async {
    final client = MockClient(
      (_) async => http.Response(
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
      ),
    );

    final adapter = QwenAdapter(configFor(ThinkingLevel.on), client: client);
    final result = await adapter.translate(
      content: {'greeting': 'Hello'},
      targetLanguage: 'ja',
    );

    expect(result, {'greeting': 'こんにちは'});
  });

  group('接続確認 (010 AC-16)', () {
    test('Chat Completion へ最小リクエストを1回だけ送る', () async {
      final recorded = recordingClient();
      final adapter = QwenAdapter(
        configFor(ThinkingLevel.on),
        client: recorded.client,
      );

      final isValid = await adapter.validateApiKey('candidate-key');

      expect(isValid, isTrue);
      expect(recorded.uris.length, 1);
      expect(
        recorded.uris.single.toString(),
        '${QwenAdapter.internationalBaseUrl}/chat/completions',
      );
      expect(
        recorded.bodies.single['max_tokens'],
        QwenAdapter.connectionCheckMaxTokens,
      );
      expect(recorded.bodies.single['enable_thinking'], isFalse);
    });

    test('モデル一覧 API は使わない', () async {
      final requestedPaths = <String>[];
      final client = MockClient((request) async {
        requestedPaths.add(request.url.path);
        return http.Response(
          jsonEncode({
            'choices': [
              {
                'message': {'content': 'ok'},
              },
            ],
          }),
          200,
        );
      });

      await QwenAdapter(
        configFor(ThinkingLevel.off),
        client: client,
      ).validateApiKey('candidate-key');

      expect(requestedPaths.any((path) => path.endsWith('/models')), isFalse);
    });

    test('HTTP エラーでは false を返す', () async {
      var callCount = 0;
      final client = MockClient((_) async {
        callCount++;
        return http.Response('{"error":"invalid"}', 401);
      });

      final adapter = QwenAdapter(configFor(ThinkingLevel.off), client: client);

      expect(await adapter.validateApiKey('bad-key'), isFalse);
      expect(callCount, 1);
    });
  });
}
