import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:villager_translator/domain/llm/llm_provider.dart';
import 'package:villager_translator/domain/llm/thinking_level.dart';
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

    test('有効な値はドラフトへ即座に反映されるが、save() を呼ぶまでディスクへ反映されない', () async {
      final controller = SettingsController(
        repository: repository,
        apiKeyStore: InMemoryApiKeyStore(),
      );
      await controller.load();

      final error = await controller.updateTranslation(
        (s) => s.copyWith(resourcePackName: 'CustomPack'),
      );
      expect(error, isNull);
      expect(controller.settings.translation.resourcePackName, 'CustomPack');

      final beforeSave = await repository.load();
      expect(beforeSave.translation.resourcePackName, 'VillagerTranslator');

      await controller.save();

      final afterSave = await repository.load();
      expect(afterSave.translation.resourcePackName, 'CustomPack');
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
      await controller.save();
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

    test('OpenAI 以外を選択中の場合、プロバイダー選択を維持したまま初期値に戻る', () async {
      final apiKeyStore = InMemoryApiKeyStore();
      final controller = SettingsController(
        repository: repository,
        apiKeyStore: apiKeyStore,
      );
      await controller.load();

      await controller.setProvider(LlmProvider.anthropic);
      await controller.setApiKey(LlmProvider.anthropic, 'secret-key');
      await controller.save();
      await controller.updateLlm((s) => s.copyWith(temperature: 0.2));

      await controller.resetToDefaults();

      expect(controller.settings.llm.provider, LlmProvider.anthropic);
      expect(controller.settings.llm.temperature, 1.0);
      expect(controller.apiKeyFor(LlmProvider.anthropic), 'secret-key');
      expect(await apiKeyStore.read(LlmProvider.anthropic), 'secret-key');
    });

    test('保存ボタンを介さず即時に永続化され、現在のテーマ設定には影響しない', () async {
      final controller = SettingsController(
        repository: repository,
        apiKeyStore: InMemoryApiKeyStore(),
      );
      await controller.load();
      await controller.setThemeMode(AppThemeMode.dark);

      await controller.updateTranslation(
        (s) => s.copyWith(resourcePackName: 'Changed'),
      );
      await controller.resetToDefaults();

      final reloaded = await repository.load();
      expect(reloaded.translation.resourcePackName, 'VillagerTranslator');
      expect(reloaded.themeMode, AppThemeMode.dark);
      expect(controller.settings.themeMode, AppThemeMode.dark);
    });
  });

  group('SettingsController.hasUnsavedChanges / discardChanges', () {
    test('ドラフトを変更すると true になり、save() 後は false に戻る', () async {
      final controller = SettingsController(
        repository: repository,
        apiKeyStore: InMemoryApiKeyStore(),
      );
      await controller.load();
      expect(controller.hasUnsavedChanges, isFalse);

      await controller.updateTranslation(
        (s) => s.copyWith(resourcePackName: 'Changed'),
      );
      expect(controller.hasUnsavedChanges, isTrue);

      await controller.save();
      expect(controller.hasUnsavedChanges, isFalse);
    });

    test('discardChanges で翻訳設定・API キーのドラフトが直近の永続化状態に戻る', () async {
      final apiKeyStore = InMemoryApiKeyStore();
      final controller = SettingsController(
        repository: repository,
        apiKeyStore: apiKeyStore,
      );
      await controller.load();
      await controller.setApiKey(LlmProvider.openai, 'saved-key');
      await controller.save();

      await controller.updateTranslation(
        (s) => s.copyWith(resourcePackName: 'Unsaved'),
      );
      await controller.setApiKey(LlmProvider.openai, 'unsaved-key');
      expect(controller.hasUnsavedChanges, isTrue);

      controller.discardChanges();

      expect(controller.hasUnsavedChanges, isFalse);
      expect(
        controller.settings.translation.resourcePackName,
        'VillagerTranslator',
      );
      expect(controller.apiKeyFor(LlmProvider.openai), 'saved-key');
      expect(await apiKeyStore.read(LlmProvider.openai), 'saved-key');
    });

    test('setThemeMode は保存ボタンを介さず即時に永続化され、未保存のドラフト変更を巻き込まない', () async {
      final controller = SettingsController(
        repository: repository,
        apiKeyStore: InMemoryApiKeyStore(),
      );
      await controller.load();

      await controller.updateTranslation(
        (s) => s.copyWith(resourcePackName: 'StillUnsaved'),
      );
      await controller.setThemeMode(AppThemeMode.dark);

      expect(controller.hasUnsavedChanges, isTrue);
      expect(controller.settings.translation.resourcePackName, 'StillUnsaved');

      final reloaded = await repository.load();
      expect(reloaded.themeMode, AppThemeMode.dark);
      expect(reloaded.translation.resourcePackName, 'VillagerTranslator');
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
        await firstController.save();

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

  group('SettingsController.lastSavedAt(保存状態インジケーター用、#9)', () {
    test('読み込み直後は null で、ドラフト変更だけでは更新されず save() で更新される', () async {
      final controller = SettingsController(
        repository: repository,
        apiKeyStore: InMemoryApiKeyStore(),
      );
      await controller.load();

      expect(controller.lastSavedAt, isNull);

      await controller.updateTranslation(
        (s) => s.copyWith(resourcePackName: 'Changed'),
      );
      expect(controller.lastSavedAt, isNull);

      await controller.save();
      expect(controller.lastSavedAt, isNotNull);
    });

    test('検証エラーで保存が行われなかった場合は更新されない', () async {
      final controller = SettingsController(
        repository: repository,
        apiKeyStore: InMemoryApiKeyStore(),
      );
      await controller.load();

      final error = await controller.updateLlm(
        (s) => s.copyWith(temperature: 9.9),
      );

      expect(error, isNotNull);
      expect(controller.lastSavedAt, isNull);
    });

    test('API キーの保存でも save() を呼ぶと更新される', () async {
      final controller = SettingsController(
        repository: repository,
        apiKeyStore: InMemoryApiKeyStore(),
      );
      await controller.load();

      await controller.setApiKey(LlmProvider.openai, 'secret-key');
      expect(controller.lastSavedAt, isNull);

      await controller.save();
      expect(controller.lastSavedAt, isNotNull);
    });
  });

  group('SettingsController の思考量(docs/specs/009)', () {
    test('選択中モデルが対応していない思考量へはエラーを返し、値が保存されない', () async {
      final controller = SettingsController(
        repository: repository,
        apiKeyStore: InMemoryApiKeyStore(),
      );
      await controller.load();
      // 既定は OpenAI / gpt-5.4-nano ではなく gpt-5.6-luna(思考量フル対応)。
      // 対応していないモデルへ切り替えて検証する。
      await controller.updateLlm(
        (s) => s.copyWith(model: 'gpt-5.4-nano', customModel: ''),
      );

      final error = await controller.updateLlm(
        (s) => s.copyWith(thinkingLevel: ThinkingLevel.high),
      );

      expect(error, isNotNull);
      expect(controller.settings.llm.thinkingLevel, ThinkingLevel.off);
    });

    test('対応しているモデルでは思考量の変更がドラフトへ反映される', () async {
      final controller = SettingsController(
        repository: repository,
        apiKeyStore: InMemoryApiKeyStore(),
      );
      await controller.load();

      final error = await controller.updateLlm(
        (s) => s.copyWith(thinkingLevel: ThinkingLevel.high),
      );

      expect(error, isNull);
      expect(controller.settings.llm.thinkingLevel, ThinkingLevel.high);
    });

    test('プロバイダー切替後、新しい既定モデルが対応していない思考量は off へリセットされる', () async {
      final controller = SettingsController(
        repository: repository,
        apiKeyStore: InMemoryApiKeyStore(),
      );
      await controller.load();
      await controller.updateLlm(
        (s) => s.copyWith(thinkingLevel: ThinkingLevel.high),
      );

      // Gemini の既定モデル(gemini-3.5-flash-lite)は思考量非対応。
      await controller.setProvider(LlmProvider.gemini);

      expect(controller.settings.llm.thinkingLevel, ThinkingLevel.off);
    });

    test('プロバイダー切替後、新しい既定モデルが対応している思考量は維持される', () async {
      final controller = SettingsController(
        repository: repository,
        apiKeyStore: InMemoryApiKeyStore(),
      );
      await controller.load();
      await controller.updateLlm(
        (s) => s.copyWith(thinkingLevel: ThinkingLevel.low),
      );

      // Anthropic の既定モデル(claude-haiku-4-5)は low に対応している。
      await controller.setProvider(LlmProvider.anthropic);

      expect(controller.settings.llm.thinkingLevel, ThinkingLevel.low);
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
