import 'package:flutter_test/flutter_test.dart';
import 'package:villager_translator/features/mod_translation/mod_translation_controller.dart';
import 'package:villager_translator/features/quest_translation/quest_translation_controller.dart';
import 'package:villager_translator/features/settings/settings_controller.dart';
import 'package:villager_translator/features/shell/profile_directory_controller.dart';

import '../../test_support/in_memory_api_key_store.dart';
import '../../test_support/in_memory_settings_repository.dart';

Future<SettingsController> _buildSettingsController() async {
  final controller = SettingsController(
    repository: InMemorySettingsRepository(),
    apiKeyStore: InMemoryApiKeyStore(),
  );
  await controller.load();
  return controller;
}

void main() {
  group('ProfileDirectoryController', () {
    test('setPath で notifyListeners が発火し、profileDirectory が更新される', () {
      final controller = ProfileDirectoryController();
      var notified = false;
      controller.addListener(() => notified = true);

      controller.setPath('C:/profile');

      expect(notified, isTrue);
      expect(controller.profileDirectory!.path, 'C:/profile');
    });

    test('同一インスタンスを複数のフィーチャーコントローラーへ注入すると、'
        '一方での選択が他方にも反映される(008 受け入れ条件2)', () async {
      final settingsController = await _buildSettingsController();
      final shared = ProfileDirectoryController();

      final modController = ModTranslationController(
        settingsController: settingsController,
        profileDirectoryController: shared,
      );
      final questController = QuestTranslationController(
        settingsController: settingsController,
        profileDirectoryController: shared,
      );

      modController.setProfileDirectoryPath('C:/shared-profile');

      expect(modController.profileDirectory!.path, 'C:/shared-profile');
      expect(questController.profileDirectory!.path, 'C:/shared-profile');
    });

    test('未指定の場合、各コントローラーは専用インスタンスを持ち、互いに影響しない', () async {
      final settingsController = await _buildSettingsController();

      final modController = ModTranslationController(
        settingsController: settingsController,
      );
      final questController = QuestTranslationController(
        settingsController: settingsController,
      );

      modController.setProfileDirectoryPath('C:/mod-only');

      expect(modController.profileDirectory!.path, 'C:/mod-only');
      expect(questController.profileDirectory, isNull);
    });
  });
}
