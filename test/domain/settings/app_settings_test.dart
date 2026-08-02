import 'package:flutter_test/flutter_test.dart';
import 'package:villager_translator/domain/llm/llm_provider.dart';
import 'package:villager_translator/domain/settings/app_settings.dart';
import 'package:villager_translator/domain/settings/existing_translation_policy.dart';
import 'package:villager_translator/domain/settings/supported_language.dart';

void main() {
  group('AppSettings', () {
    test('defaults() は仕様書の既定値を反映する', () {
      final settings = AppSettings.defaults();

      expect(settings.llm.provider, LlmProvider.openai);
      expect(settings.llm.maxRetries, 3);
      expect(settings.llm.temperature, 1.0);
      expect(
        settings.translation.existingTranslationPolicy,
        ExistingTranslationPolicy.diffUpdate,
      );
      expect(settings.translation.resourcePackName, 'VillagerTranslator');
      expect(settings.translation.modChunkSize, 50);
      expect(settings.translation.questChunkSize, 1);
      expect(settings.translation.guidebookChunkSize, 1);
      expect(settings.translation.maxTokensPerChunk, 3000);
      expect(settings.translation.fallbackToEntryBased, isTrue);
      expect(settings.translation.useTokenBasedChunking, isFalse);
    });

    test('toJson/fromJson の往復で内容が保持される', () {
      final original = AppSettings.defaults().copyWith(
        translation: AppSettings.defaults().translation.copyWith(
          customLanguages: const [
            SupportedLanguage(
              id: 'xx_xx',
              displayName: 'Xx語',
              isDefault: false,
            ),
          ],
        ),
      );

      final restored = AppSettings.fromJson(original.toJson());

      expect(restored.llm.provider, original.llm.provider);
      expect(restored.llm.model, original.llm.model);
      expect(
        restored.translation.resourcePackName,
        original.translation.resourcePackName,
      );
      expect(
        restored.translation.customLanguages,
        original.translation.customLanguages,
      );
    });

    test('toJson は API キーを含まない構造である(LlmSettings に apiKey フィールドが存在しない)', () {
      final json = AppSettings.defaults().toJson();
      final llmJson = json['llm'] as Map<String, dynamic>;

      expect(llmJson.containsKey('apiKey'), isFalse);
      expect(llmJson.containsKey('apiKeys'), isFalse);
    });

    test('壊れた JSON からは例外を投げずに既定値へフォールバックする', () {
      final restored = AppSettings.fromJson({
        'llm': 'invalid',
        'translation': 123,
      });
      expect(restored.llm.provider, AppSettings.defaults().llm.provider);
    });

    test('未知の existingTranslationPolicy 値は diffUpdate にフォールバックする', () {
      final json = AppSettings.defaults().toJson();
      (json['translation']
              as Map<String, dynamic>)['existingTranslationPolicy'] =
          'unknown';

      final restored = AppSettings.fromJson(json);
      expect(
        restored.translation.existingTranslationPolicy,
        ExistingTranslationPolicy.diffUpdate,
      );
    });
  });

  group('kDefaultLanguages', () {
    test('既定9言語がすべて isDefault: true である', () {
      expect(kDefaultLanguages.length, 9);
      expect(kDefaultLanguages.every((lang) => lang.isDefault), isTrue);
    });
  });
}
