import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:villager_translator/domain/llm/llm_adapter_config.dart';
import 'package:villager_translator/domain/llm/llm_provider.dart';
import 'package:villager_translator/domain/llm/model_catalog.dart';
import 'package:villager_translator/domain/llm/thinking_level.dart';
import 'package:villager_translator/infrastructure/llm/deepseek_adapter.dart';
import 'package:villager_translator/infrastructure/llm/kimi_adapter.dart';
import 'package:villager_translator/infrastructure/llm/openai_adapter.dart';
import 'package:villager_translator/infrastructure/llm/openai_compatible_adapter_base.dart';
import 'package:villager_translator/infrastructure/llm/qwen_adapter.dart';

typedef _AdapterBuilder =
    OpenAiCompatibleAdapterBase Function(LlmAdapterConfig, http.Client);

/// OpenAI 互換アダプター4種に共通する振る舞い(010 §7.1、AC-13・AC-14)。
void main() {
  final adapterBuilders = <LlmProvider, _AdapterBuilder>{
    LlmProvider.openai: (config, client) =>
        OpenAiAdapter(config, client: client),
    LlmProvider.deepseek: (config, client) =>
        DeepSeekAdapter(config, client: client),
    LlmProvider.qwen: (config, client) => QwenAdapter(config, client: client),
    LlmProvider.kimi: (config, client) => KimiAdapter(config, client: client),
  };

  LlmAdapterConfig configFor(LlmProvider provider) {
    final model = kDefaultModel[provider]!;
    final capabilities = capabilitiesFor(provider, model);
    return LlmAdapterConfig(
      apiKey: 'test-key',
      model: model,
      temperature: 0.5,
      maxRetries: 3,
      thinkingLevel: capabilities.defaultThinkingLevel,
      capabilities: capabilities,
    );
  }

  http.Client contentClient(
    void Function(http.Request request) onRequest, {
    String content = 'greeting: こんにちは',
  }) {
    return MockClient((request) async {
      onRequest(request);
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
  }

  for (final entry in adapterBuilders.entries) {
    final provider = entry.key;

    group('${provider.id} アダプター', () {
      test('chat/completions へ Bearer 認証で POST する', () async {
        late http.Request captured;
        final adapter = entry.value(
          configFor(provider),
          contentClient((request) => captured = request),
        );

        await adapter.translate(
          content: {'greeting': 'Hello'},
          targetLanguage: 'ja',
        );

        expect(captured.method, 'POST');
        expect(captured.url.path, endsWith('/chat/completions'));
        expect(captured.headers['Authorization'], 'Bearer test-key');
      });

      test('system と user の2メッセージを送信する', () async {
        late Map<String, dynamic> body;
        final adapter = entry.value(
          configFor(provider),
          contentClient(
            (request) =>
                body = jsonDecode(request.body) as Map<String, dynamic>,
          ),
        );

        await adapter.translate(
          content: {'greeting': 'Hello'},
          targetLanguage: 'ja',
        );

        final messages = body['messages'] as List<dynamic>;
        expect(messages.length, 2);
        expect(messages[0]['role'], 'system');
        expect(messages[1]['role'], 'user');
      });

      test('翻訳結果は message.content のみで reasoning_content を含まない', () async {
        final adapter = entry.value(configFor(provider), contentClient((_) {}));

        final result = await adapter.translate(
          content: {'greeting': 'Hello'},
          targetLanguage: 'ja',
        );

        expect(result, {'greeting': 'こんにちは'});
      });
    });
  }

  test('temperature 非対応のモデルへはサンプリングパラメーターを送信しない', () async {
    late Map<String, dynamic> body;
    final adapter = OpenAiAdapter(
      const LlmAdapterConfig(
        apiKey: 'test-key',
        model: 'no-temperature-model',
        temperature: 0.5,
        maxRetries: 3,
        capabilities: ModelCapabilities(
          thinkingLevels: [ThinkingLevel.off],
          defaultThinkingLevel: ThinkingLevel.off,
          supportsTemperature: false,
        ),
      ),
      client: contentClient(
        (request) => body = jsonDecode(request.body) as Map<String, dynamic>,
      ),
    );

    await adapter.translate(
      content: {'greeting': 'Hello'},
      targetLanguage: 'ja',
    );

    expect(body.containsKey('temperature'), isFalse);
  });
}
