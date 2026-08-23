import 'package:flutter_test/flutter_test.dart';
import 'package:villager_translator/domain/llm/llm_provider.dart';
import 'package:villager_translator/domain/llm/model_catalog.dart';
import 'package:villager_translator/domain/llm/thinking_level.dart';
import 'package:villager_translator/domain/settings/llm_settings.dart';

void main() {
  LlmSettings settingsFor(
    LlmProvider provider,
    String model, {
    String qwenBaseUrl = '',
    ThinkingLevel thinkingLevel = ThinkingLevel.off,
  }) {
    return LlmSettings.defaults().copyWith(
      provider: provider,
      model: model,
      thinkingLevel: thinkingLevel,
      qwenBaseUrl: qwenBaseUrl,
    );
  }

  group('LlmSettings.toAdapterConfig (010 §7.3、AC-18)', () {
    test('モデル・温度・リトライ回数・思考量をそのまま渡す', () {
      final settings = settingsFor(
        LlmProvider.deepseek,
        'deepseek-v4-pro',
        thinkingLevel: ThinkingLevel.max,
      ).copyWith(temperature: 0.4, maxRetries: 5);

      final config = settings.toAdapterConfig(apiKey: 'secret');

      expect(config.apiKey, 'secret');
      expect(config.model, 'deepseek-v4-pro');
      expect(config.temperature, 0.4);
      expect(config.maxRetries, 5);
      expect(config.thinkingLevel, ThinkingLevel.max);
    });

    test('カスタムモデル選択時は自由入力のモデル名を渡す', () {
      final settings = LlmSettings.defaults().copyWith(
        model: kCustomModelSentinel,
        customModel: 'my-model',
      );

      expect(settings.toAdapterConfig(apiKey: 'k').model, 'my-model');
    });

    test('選択中モデルの能力情報を渡す', () {
      final config = settingsFor(
        LlmProvider.gemini,
        'gemini-3.7-flash',
        thinkingLevel: ThinkingLevel.medium,
      ).toAdapterConfig(apiKey: 'k');

      expect(config.capabilities.supportsTemperature, isFalse);
    });

    test('Qwen 選択時はベース URL の上書きを渡す (010 AC-15)', () {
      final config = settingsFor(
        LlmProvider.qwen,
        'qwen3.8-max',
        qwenBaseUrl: 'https://example.test/compatible-mode/v1',
      ).toAdapterConfig(apiKey: 'k');

      expect(config.baseUrl, 'https://example.test/compatible-mode/v1');
    });

    test('Qwen ベース URL が空欄なら上書きしない', () {
      final config = settingsFor(
        LlmProvider.qwen,
        'qwen3.8-max',
      ).toAdapterConfig(apiKey: 'k');

      expect(config.baseUrl, isNull);
    });

    test('Qwen ベース URL は前後の空白を除去して渡す', () {
      final config = settingsFor(
        LlmProvider.qwen,
        'qwen3.8-max',
        qwenBaseUrl: '  https://example.test/v1  ',
      ).toAdapterConfig(apiKey: 'k');

      expect(config.baseUrl, 'https://example.test/v1');
    });

    test('Qwen 以外のプロバイダーへはベース URL を渡さない (010 AC-15)', () {
      for (final provider in LlmProvider.values) {
        if (provider == LlmProvider.qwen) continue;
        final config = settingsFor(
          provider,
          kDefaultModel[provider]!,
          qwenBaseUrl: 'https://example.test/v1',
        ).toAdapterConfig(apiKey: 'k');

        expect(
          config.baseUrl,
          isNull,
          reason: '${provider.id} へ Qwen のベース URL が渡っている',
        );
      }
    });
  });

  group('LlmSettings の永続化', () {
    test('qwenBaseUrl は JSON へ往復する', () {
      final settings = settingsFor(
        LlmProvider.qwen,
        'qwen3.8-max',
        qwenBaseUrl: 'https://example.test/v1',
      );

      final restored = LlmSettings.fromJson(settings.toJson());

      expect(restored.qwenBaseUrl, 'https://example.test/v1');
      expect(restored.provider, LlmProvider.qwen);
    });

    test('qwenBaseUrl が無い旧設定ファイルは空欄として読み込む', () {
      final json = LlmSettings.defaults().toJson()..remove('qwenBaseUrl');

      expect(LlmSettings.fromJson(json).qwenBaseUrl, '');
    });

    test('新しいプロバイダー識別子を復元できる', () {
      for (final provider in LlmProvider.values) {
        final json = LlmSettings.defaults()
            .copyWith(provider: provider, model: kDefaultModel[provider]!)
            .toJson();

        expect(LlmSettings.fromJson(json).provider, provider);
      }
    });
  });
}
