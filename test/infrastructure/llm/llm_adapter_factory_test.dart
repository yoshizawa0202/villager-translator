import 'package:flutter_test/flutter_test.dart';
import 'package:villager_translator/domain/llm/llm_adapter_config.dart';
import 'package:villager_translator/domain/llm/llm_provider.dart';
import 'package:villager_translator/infrastructure/llm/anthropic_adapter.dart';
import 'package:villager_translator/infrastructure/llm/gemini_adapter.dart';
import 'package:villager_translator/infrastructure/llm/llm_adapter_factory.dart';
import 'package:villager_translator/infrastructure/llm/openai_adapter.dart';

void main() {
  const config = LlmAdapterConfig(
    apiKey: 'k',
    model: 'm',
    temperature: 1.0,
    maxRetries: 3,
  );

  test('プロバイダーごとに対応するアダプター実装を生成する', () {
    final factory = DefaultLlmAdapterFactory();

    expect(factory.create(LlmProvider.openai, config), isA<OpenAiAdapter>());
    expect(
      factory.create(LlmProvider.anthropic, config),
      isA<AnthropicAdapter>(),
    );
    expect(factory.create(LlmProvider.gemini, config), isA<GeminiAdapter>());
  });

  test('生成したアダプターの provider が要求したプロバイダーと一致する', () {
    final factory = DefaultLlmAdapterFactory();

    for (final provider in LlmProvider.values) {
      expect(factory.create(provider, config).provider, provider);
    }
  });
}
