import 'package:flutter_test/flutter_test.dart';
import 'package:villager_translator/domain/llm/llm_provider.dart';
import 'package:villager_translator/domain/llm/model_catalog.dart';
import 'package:villager_translator/domain/llm/thinking_level.dart';
import 'package:villager_translator/domain/settings/settings_validator.dart';
import 'package:villager_translator/domain/settings/supported_language.dart';

void main() {
  group('SettingsValidator.validateTemperature', () {
    test('0.0〜2.0 の範囲内は有効', () {
      expect(SettingsValidator.validateTemperature(0.0), isNull);
      expect(SettingsValidator.validateTemperature(1.0), isNull);
      expect(SettingsValidator.validateTemperature(2.0), isNull);
    });

    test('範囲外はエラーメッセージを返す', () {
      expect(SettingsValidator.validateTemperature(-0.1), isNotNull);
      expect(SettingsValidator.validateTemperature(2.1), isNotNull);
    });
  });

  group('SettingsValidator.validateMaxRetries', () {
    test('0〜10 の範囲内は有効', () {
      expect(SettingsValidator.validateMaxRetries(0), isNull);
      expect(SettingsValidator.validateMaxRetries(10), isNull);
    });

    test('範囲外はエラーメッセージを返す', () {
      expect(SettingsValidator.validateMaxRetries(-1), isNotNull);
      expect(SettingsValidator.validateMaxRetries(11), isNotNull);
    });
  });

  group('SettingsValidator.validateCustomModel', () {
    test('カスタム選択時に空文字はエラー', () {
      expect(
        SettingsValidator.validateCustomModel(kCustomModelSentinel, ''),
        isNotNull,
      );
      expect(
        SettingsValidator.validateCustomModel(kCustomModelSentinel, '   '),
        isNotNull,
      );
    });

    test('カスタム選択時に非空文字は有効', () {
      expect(
        SettingsValidator.validateCustomModel(kCustomModelSentinel, 'my-model'),
        isNull,
      );
    });

    test('カスタム未選択時は customModel が空でも有効', () {
      expect(SettingsValidator.validateCustomModel('gpt-4o-mini', ''), isNull);
    });
  });

  group('SettingsValidator.validateThinkingLevel', () {
    test('モデルが対応しているレベルは有効', () {
      expect(
        SettingsValidator.validateThinkingLevel(
          LlmProvider.openai,
          'gpt-5.4-nano',
          ThinkingLevel.off,
        ),
        isNull,
      );
      expect(
        SettingsValidator.validateThinkingLevel(
          LlmProvider.openai,
          'gpt-5.6-sol',
          ThinkingLevel.high,
        ),
        isNull,
      );
    });

    test('モデルが対応していないレベルはエラー', () {
      expect(
        SettingsValidator.validateThinkingLevel(
          LlmProvider.openai,
          'gpt-5.4-nano',
          ThinkingLevel.high,
        ),
        isNotNull,
      );
    });

    test('思考を無効化できないモデルでは off もエラー (010 §5.1)', () {
      expect(
        SettingsValidator.validateThinkingLevel(
          LlmProvider.gemini,
          'gemini-3.7-flash',
          ThinkingLevel.off,
        ),
        isNotNull,
      );
      expect(
        SettingsValidator.validateThinkingLevel(
          LlmProvider.kimi,
          'kimi-k3',
          ThinkingLevel.off,
        ),
        isNotNull,
      );
    });

    test('モデル能力情報どおりのレベルは新プロバイダーでも有効 (010 AC-07)', () {
      expect(
        SettingsValidator.validateThinkingLevel(
          LlmProvider.deepseek,
          'deepseek-v4-flash',
          ThinkingLevel.max,
        ),
        isNull,
      );
      expect(
        SettingsValidator.validateThinkingLevel(
          LlmProvider.qwen,
          'qwen3.8-max',
          ThinkingLevel.on,
        ),
        isNull,
      );
      expect(
        SettingsValidator.validateThinkingLevel(
          LlmProvider.qwen,
          'qwen3.8-max',
          ThinkingLevel.high,
        ),
        isNotNull,
      );
    });

    test('カスタムモデル選択時は制限しない', () {
      expect(
        SettingsValidator.validateThinkingLevel(
          LlmProvider.openai,
          kCustomModelSentinel,
          ThinkingLevel.high,
        ),
        isNull,
      );
    });

    test('カタログに存在しない未知のモデルは制限しない', () {
      expect(
        SettingsValidator.validateThinkingLevel(
          LlmProvider.openai,
          'unknown-model',
          ThinkingLevel.high,
        ),
        isNull,
      );
    });
  });

  group('SettingsValidator.validateQwenBaseUrl (010 AC-15)', () {
    test('空欄は有効(既定エンドポイントを使う)', () {
      expect(SettingsValidator.validateQwenBaseUrl(''), isNull);
      expect(SettingsValidator.validateQwenBaseUrl('   '), isNull);
    });

    test('http/https の絶対 URL は有効', () {
      expect(
        SettingsValidator.validateQwenBaseUrl(
          'https://dashscope-intl.aliyuncs.com/compatible-mode/v1',
        ),
        isNull,
      );
      expect(
        SettingsValidator.validateQwenBaseUrl('http://localhost:8080/v1'),
        isNull,
      );
    });

    test('不正な URL は日本語の検証エラーになる', () {
      expect(SettingsValidator.validateQwenBaseUrl('not a url'), isNotNull);
      expect(
        SettingsValidator.validateQwenBaseUrl('example.com/v1'),
        isNotNull,
      );
      expect(
        SettingsValidator.validateQwenBaseUrl('ftp://example.com/v1'),
        isNotNull,
      );
      expect(SettingsValidator.validateQwenBaseUrl('https://'), isNotNull);
    });
  });

  group('SettingsValidator.validateCustomLanguage', () {
    test('非空かつ重複しない ID・表示名は有効', () {
      expect(
        SettingsValidator.validateCustomLanguage(
          'xx_xx',
          'Xx語',
          kDefaultLanguages,
        ),
        isNull,
      );
    });

    test('ID が空はエラー', () {
      expect(
        SettingsValidator.validateCustomLanguage('', '表示名', kDefaultLanguages),
        isNotNull,
      );
    });

    test('表示名が空はエラー', () {
      expect(
        SettingsValidator.validateCustomLanguage(
          'xx_xx',
          '',
          kDefaultLanguages,
        ),
        isNotNull,
      );
    });

    test('既定言語と大小無視で重複する ID はエラー', () {
      expect(
        SettingsValidator.validateCustomLanguage(
          'JA_JP',
          '日本語(重複)',
          kDefaultLanguages,
        ),
        isNotNull,
      );
    });
  });
}
