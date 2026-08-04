import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:villager_translator/domain/llm/llm_provider.dart';
import 'package:villager_translator/domain/settings/app_settings.dart';
import 'package:villager_translator/features/settings/settings_controller.dart';
import 'package:villager_translator/infrastructure/settings/settings_repository.dart';

import '../../test_support/in_memory_api_key_store.dart';

void main() {
  late Directory tempDir;
  late SettingsRepository repository;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync(
      'villager_translator_controller_test',
    );
    repository = SettingsRepository.forApplicationSupportDirectory(tempDir);
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('SettingsController の検証', () {
    test('temperature が範囲外の場合はエラーを返し、値が保存されない', () async {
      final controller = SettingsController(
        repository: repository,
        apiKeyStore: InMemoryApiKeyStore(),
      );
      await controller.load();

      final error = await controller.updateLlm(
        (s) => s.copyWith(temperature: 9.9),
      );

      expect(error, isNotNull);
      expect(controller.settings.llm.temperature, 1.0);
    });

    test('maxRetries が範囲外の場合はエラーを返し、値が保存されない', () async {
      final controller = SettingsController(
        repository: repository,
        apiKeyStore: InMemoryApiKeyStore(),
      );
      await controller.load();

      final error = await controller.updateLlm(
        (s) => s.copyWith(maxRetries: 999),
      );

      expect(error, isNotNull);
      expect(controller.settings.llm.maxRetries, 3);
    });

    test('有効な値は保存され、再読み込みでも反映される', () async {
      final controller = SettingsController(
        repository: repository,
        apiKeyStore: InMemoryApiKeyStore(),
      );
      await controller.load();

      final error = await controller.updateTranslation(
        (s) => s.copyWith(resourcePackName: 'CustomPack'),
      );
      expect(error, isNull);

      final reloaded = await repository.load();
      expect(reloaded.translation.resourcePackName, 'CustomPack');
    });
  });

  group('SettingsController.resetToDefaults', () {
    test('LLM設定・翻訳設定は初期値に戻るが、保存済み API キーは保持される', () async {
      final apiKeyStore = InMemoryApiKeyStore();
      final controller = SettingsController(
        repository: repository,
        apiKeyStore: apiKeyStore,
      );
      await controller.load();

      await controller.setApiKey(LlmProvider.openai, 'secret-key');
      await controller.updateTranslation(
        (s) => s.copyWith(resourcePackName: 'Changed'),
      );

      await controller.resetToDefaults();

      expect(
        controller.settings.translation.resourcePackName,
        'VillagerTranslator',
      );
      expect(controller.apiKeyFor(LlmProvider.openai), 'secret-key');
      expect(await apiKeyStore.read(LlmProvider.openai), 'secret-key');
    });
  });

  group('SettingsController.setThemeMode', () {
    test('テーマ切替が保存され、再読み込みでも反映される', () async {
      final controller = SettingsController(
        repository: repository,
        apiKeyStore: InMemoryApiKeyStore(),
      );
      await controller.load();

      await controller.setThemeMode(AppThemeMode.dark);
      expect(controller.settings.themeMode, AppThemeMode.dark);

      final reloaded = SettingsController(
        repository: repository,
        apiKeyStore: InMemoryApiKeyStore(),
      );
      await reloaded.load();
      expect(reloaded.settings.themeMode, AppThemeMode.dark);
    });
  });

  group('API キーの永続化(再起動の模擬)', () {
    test(
      '同一の ApiKeyStore を共有した新しい SettingsController でも API キーを復元できる',
      () async {
        final sharedApiKeyStore = InMemoryApiKeyStore();

        final firstController = SettingsController(
          repository: repository,
          apiKeyStore: sharedApiKeyStore,
        );
        await firstController.load();
        await firstController.setApiKey(
          LlmProvider.anthropic,
          'restart-test-key',
        );

        final secondController = SettingsController(
          repository: repository,
          apiKeyStore: sharedApiKeyStore,
        );
        await secondController.load();

        expect(
          secondController.apiKeyFor(LlmProvider.anthropic),
          'restart-test-key',
        );
      },
    );

    test('API キーは AppSettings ではなく ApiKeyStore からのみ供給される', () async {
      final apiKeyStore = InMemoryApiKeyStore();
      final controller = SettingsController(
        repository: repository,
        apiKeyStore: apiKeyStore,
      );
      await controller.load();
      await controller.setApiKey(LlmProvider.gemini, 'gemini-key');

      final settingsJson = controller.settings.toJson();
      expect(settingsJson.toString().contains('gemini-key'), isFalse);
    });
  });

  group('SettingsController.addCustomLanguage / removeCustomLanguage', () {
    test('有効なカスタム言語を追加でき、一覧に反映される', () async {
      final controller = SettingsController(
        repository: repository,
        apiKeyStore: InMemoryApiKeyStore(),
      );
      await controller.load();

      final error = await controller.addCustomLanguage('xx_xx', 'Xx語');

      expect(error, isNull);
      expect(
        controller.settings.translation.customLanguages.map((l) => l.id),
        contains('xx_xx'),
      );
    });

    test('既定言語と重複する ID は追加できない', () async {
      final controller = SettingsController(
        repository: repository,
        apiKeyStore: InMemoryApiKeyStore(),
      );
      await controller.load();

      final error = await controller.addCustomLanguage('ja_jp', '重複');
      expect(error, isNotNull);
      expect(controller.settings.translation.customLanguages, isEmpty);
    });

    test('追加したカスタム言語を削除できる', () async {
      final controller = SettingsController(
        repository: repository,
        apiKeyStore: InMemoryApiKeyStore(),
      );
      await controller.load();
      await controller.addCustomLanguage('xx_xx', 'Xx語');

      await controller.removeCustomLanguage('xx_xx');

      expect(controller.settings.translation.customLanguages, isEmpty);
    });
  });
}
