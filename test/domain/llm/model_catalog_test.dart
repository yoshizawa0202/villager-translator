import 'package:flutter_test/flutter_test.dart';
import 'package:villager_translator/domain/llm/llm_provider.dart';
import 'package:villager_translator/domain/llm/model_catalog.dart';
import 'package:villager_translator/domain/llm/thinking_level.dart';

void main() {
  group('kModelCatalog', () {
    test('既定の思考量は必ず選択肢に含まれる', () {
      for (final entry in kModelCatalog.entries) {
        for (final model in entry.value) {
          expect(
            model.capabilities.thinkingLevels,
            isNotEmpty,
            reason: '${model.id} の思考量選択肢が空',
          );
          expect(
            model.capabilities.thinkingLevels,
            contains(model.capabilities.defaultThinkingLevel),
            reason: '${model.id} の既定思考量が選択肢に含まれていない',
          );
        }
      }
    });

    test('既定モデル(kDefaultModel)は全プロバイダー分あり、カタログに存在する', () {
      for (final provider in LlmProvider.values) {
        final defaultModel = kDefaultModel[provider];
        expect(defaultModel, isNotNull, reason: '${provider.id} の既定モデルが無い');
        expect(
          modelInfoFor(provider, defaultModel!),
          isNotNull,
          reason: '${provider.id} の既定モデル $defaultModel がカタログに無い',
        );
      }
    });

    test('対象モデルがカタログへ定義されている (010 AC-01)', () {
      expect(
        modelInfoFor(LlmProvider.deepseek, 'deepseek-v4-flash'),
        isNotNull,
      );
      expect(modelInfoFor(LlmProvider.deepseek, 'deepseek-v4-pro'), isNotNull);
      expect(modelInfoFor(LlmProvider.qwen, 'qwen3.8-max'), isNotNull);
      expect(modelInfoFor(LlmProvider.gemini, 'gemini-3.7-flash'), isNotNull);
      expect(modelInfoFor(LlmProvider.kimi, 'kimi-k3'), isNotNull);
    });

    test('Qwen と Kimi は要件のモデルのみに整理されている (010 AC-02)', () {
      expect(
        kModelCatalog[LlmProvider.qwen]!.map((m) => m.id),
        equals(['qwen3.8-max']),
      );
      expect(
        kModelCatalog[LlmProvider.kimi]!.map((m) => m.id),
        equals(['kimi-k3']),
      );
      expect(modelInfoFor(LlmProvider.qwen, 'qwen-plus'), isNull);
      expect(modelInfoFor(LlmProvider.kimi, 'kimi-k2.5'), isNull);
    });

    test('Gemini の既定モデルは Gemini 3.7 Flash (010 §5.1)', () {
      expect(kDefaultModel[LlmProvider.gemini], 'gemini-3.7-flash');
    });
  });

  group('ModelCapabilities (010 AC-05)', () {
    test('DeepSeek V4 Flash / Pro は OFF・高・最大、temperature 対応', () {
      for (final id in ['deepseek-v4-flash', 'deepseek-v4-pro']) {
        final capabilities = capabilitiesFor(LlmProvider.deepseek, id);
        expect(
          capabilities.thinkingLevels,
          equals([ThinkingLevel.off, ThinkingLevel.high, ThinkingLevel.max]),
        );
        expect(capabilities.defaultThinkingLevel, ThinkingLevel.off);
        expect(capabilities.supportsTemperature, isTrue);
        expect(capabilities.supportsThinkingOff, isTrue);
      }
    });

    test('Qwen3.8-Max は OFF・ON、temperature 対応', () {
      final capabilities = capabilitiesFor(LlmProvider.qwen, 'qwen3.8-max');
      expect(
        capabilities.thinkingLevels,
        equals([ThinkingLevel.off, ThinkingLevel.on]),
      );
      expect(capabilities.defaultThinkingLevel, ThinkingLevel.off);
      expect(capabilities.supportsTemperature, isTrue);
    });

    test('Gemini 3.7 Flash は 低・中・高、既定は中、temperature 非対応', () {
      final capabilities = capabilitiesFor(
        LlmProvider.gemini,
        'gemini-3.7-flash',
      );
      expect(
        capabilities.thinkingLevels,
        equals([ThinkingLevel.low, ThinkingLevel.medium, ThinkingLevel.high]),
      );
      expect(capabilities.defaultThinkingLevel, ThinkingLevel.medium);
      expect(capabilities.supportsTemperature, isFalse);
      expect(capabilities.supportsThinkingOff, isFalse);
    });

    test('Kimi K3 は 低・高・最大、既定は最大、temperature 対応', () {
      final capabilities = capabilitiesFor(LlmProvider.kimi, 'kimi-k3');
      expect(
        capabilities.thinkingLevels,
        equals([ThinkingLevel.low, ThinkingLevel.high, ThinkingLevel.max]),
      );
      expect(capabilities.defaultThinkingLevel, ThinkingLevel.max);
      expect(capabilities.supportsTemperature, isTrue);
      expect(capabilities.supportsThinkingOff, isFalse);
    });

    test('既存 Gemini モデルの能力は変更しない (010 AC-11)', () {
      final capabilities = capabilitiesFor(
        LlmProvider.gemini,
        'gemini-3.6-flash',
      );
      expect(
        capabilities.thinkingLevels,
        equals([
          ThinkingLevel.off,
          ThinkingLevel.low,
          ThinkingLevel.medium,
          ThinkingLevel.high,
        ]),
      );
      expect(capabilities.supportsTemperature, isTrue);
    });

    test('supportsLevel は選択肢の有無を返す', () {
      final capabilities = capabilitiesFor(LlmProvider.kimi, 'kimi-k3');
      expect(capabilities.supportsLevel(ThinkingLevel.max), isTrue);
      expect(capabilities.supportsLevel(ThinkingLevel.off), isFalse);
      expect(capabilities.supportsLevel(ThinkingLevel.medium), isFalse);
    });

    test('supportsThinking は off のみの場合 false', () {
      expect(
        capabilitiesFor(LlmProvider.openai, 'gpt-5.4-nano').supportsThinking,
        isFalse,
      );
      expect(
        capabilitiesFor(LlmProvider.openai, 'gpt-5.6-sol').supportsThinking,
        isTrue,
      );
    });
  });

  group('modelInfoFor / capabilitiesFor', () {
    test('カタログに存在するモデルの ModelInfo を返す', () {
      final info = modelInfoFor(LlmProvider.openai, 'gpt-5.6-sol');
      expect(info, isNotNull);
      expect(info!.id, 'gpt-5.6-sol');
    });

    test('カタログに存在しないモデル ID には null を返す', () {
      expect(modelInfoFor(LlmProvider.openai, 'unknown-model'), isNull);
      expect(modelInfoFor(LlmProvider.openai, kCustomModelSentinel), isNull);
    });

    test('未知のモデルの能力情報は制限しない既定値になる', () {
      final capabilities = capabilitiesFor(LlmProvider.openai, 'unknown-model');
      expect(capabilities.supportsTemperature, isTrue);
      expect(capabilities.thinkingLevels, equals(ThinkingLevel.values));
    });
  });
}
