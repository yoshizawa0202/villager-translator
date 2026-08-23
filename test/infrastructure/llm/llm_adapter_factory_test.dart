import 'package:flutter_test/flutter_test.dart';
import 'package:villager_translator/domain/llm/llm_adapter_config.dart';
import 'package:villager_translator/domain/llm/llm_provider.dart';
import 'package:villager_translator/infrastructure/llm/anthropic_adapter.dart';
import 'package:villager_translator/infrastructure/llm/deepseek_adapter.dart';
import 'package:villager_translator/infrastructure/llm/gemini_adapter.dart';
import 'package:villager_translator/infrastructure/llm/kimi_adapter.dart';
import 'package:villager_translator/infrastructure/llm/llm_adapter_factory.dart';
import 'package:villager_translator/infrastructure/llm/openai_adapter.dart';
import 'package:villager_translator/infrastructure/llm/openai_compatible_adapter_base.dart';
import 'package:villager_translator/infrastructure/llm/qwen_adapter.dart';

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
    expect(
      factory.create(LlmProvider.deepseek, config),
      isA<DeepSeekAdapter>(),
    );
    expect(factory.create(LlmProvider.qwen, config), isA<QwenAdapter>());
    expect(factory.create(LlmProvider.kimi, config), isA<KimiAdapter>());
  });

  test('生成したアダプターの provider が要求したプロバイダーと一致する', () {
    final factory = DefaultLlmAdapterFactory();

    for (final provider in LlmProvider.values) {
      expect(factory.create(provider, config).provider, provider);
    }
  });

  test('OpenAI 互換の4アダプターは共通基底クラスを使う (010 AC-13)', () {
    final factory = DefaultLlmAdapterFactory();

    for (final provider in [
      LlmProvider.openai,
      LlmProvider.deepseek,
      LlmProvider.qwen,
      LlmProvider.kimi,
    ]) {
      expect(
        factory.create(provider, config),
        isA<OpenAiCompatibleAdapterBase>(),
        reason: '${provider.id} が共通基底クラスを使っていない',
      );
    }
  });
}
