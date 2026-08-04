import 'package:flutter_test/flutter_test.dart';
import 'package:villager_translator/domain/llm/model_catalog.dart';
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
