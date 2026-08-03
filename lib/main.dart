import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import 'features/mod_translation/mod_translation_page.dart';
import 'features/settings/settings_controller.dart';
import 'features/settings/settings_page.dart';
import 'infrastructure/settings/secure_api_key_store.dart';
import 'infrastructure/settings/settings_repository.dart';

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
      child: MaterialApp(
        title: 'Villager Translator',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2E7D32)),
          useMaterial3: true,
        ),
        home: const ProjectHomePage(),
      ),
    );
  }
}

class ProjectHomePage extends StatelessWidget {
  const ProjectHomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Villager Translator'),
        actions: [
          IconButton(
            key: const Key('openSettingsButton'),
            icon: const Icon(Icons.settings),
            tooltip: '設定',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (context) => const SettingsPage()),
              );
            },
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: const Padding(
            padding: EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Minecraft MOD 翻訳',
                  style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 16),
                Text(
                  '仕様駆動開発で再構築中です。最初の機能仕様を確定後、'
                  'MOD、クエスト、Patchouli ガイドブックの翻訳機能を実装します。',
                  style: TextStyle(fontSize: 16, height: 1.6),
                ),
                SizedBox(height: 24),
                Chip(label: Text('Windows デスクトップ版')),
                SizedBox(height: 24),
                _OpenModTranslationButton(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _OpenModTranslationButton extends StatelessWidget {
  const _OpenModTranslationButton();

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      key: const Key('openModTranslationButton'),
      onPressed: () {
        Navigator.of(context).push(
          MaterialPageRoute(builder: (context) => const ModTranslationPage()),
        );
      },
      child: const Text('MOD 翻訳'),
    );
  }
}
