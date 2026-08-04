import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import 'domain/settings/app_settings.dart';
import 'features/settings/settings_controller.dart';
import 'features/shell/main_shell_page.dart';
import 'infrastructure/settings/secure_api_key_store.dart';
import 'infrastructure/settings/settings_repository.dart';

/// [AppThemeMode](ドメイン層、Flutter 非依存)を Flutter の [ThemeMode] へ変換する。
ThemeMode _toFlutterThemeMode(AppThemeMode mode) {
  switch (mode) {
    case AppThemeMode.system:
      return ThemeMode.system;
    case AppThemeMode.light:
      return ThemeMode.light;
    case AppThemeMode.dark:
      return ThemeMode.dark;
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final supportDirectory = await getApplicationSupportDirectory();
  final settingsController = SettingsController(
    repository: SettingsRepository.forApplicationSupportDirectory(
      supportDirectory,
    ),
    apiKeyStore: SecureApiKeyStore(),
  );
  await settingsController.load();

  runApp(VillagerTranslatorApp(settingsController: settingsController));
}

class VillagerTranslatorApp extends StatelessWidget {
  const VillagerTranslatorApp({super.key, required this.settingsController});

  final SettingsController settingsController;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<SettingsController>.value(
      value: settingsController,
      child: Consumer<SettingsController>(
        builder: (context, settings, _) {
          return MaterialApp(
            title: 'Villager Translator',
            theme: ThemeData(
              colorScheme: ColorScheme.fromSeed(
                seedColor: const Color(0xFF2E7D32),
              ),
              useMaterial3: true,
            ),
            darkTheme: ThemeData(
              colorScheme: ColorScheme.fromSeed(
                seedColor: const Color(0xFF2E7D32),
                brightness: Brightness.dark,
              ),
              useMaterial3: true,
            ),
            themeMode: _toFlutterThemeMode(settings.settings.themeMode),
            home: const MainShellPage(),
          );
        },
      ),
    );
  }
}
