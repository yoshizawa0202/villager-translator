import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:villager_translator/domain/llm/llm_adapter.dart';
import 'package:villager_translator/domain/llm/llm_adapter_config.dart';
import 'package:villager_translator/domain/llm/llm_provider.dart';
import 'package:villager_translator/features/mod_translation/mod_translation_controller.dart';
import 'package:villager_translator/features/settings/settings_controller.dart';
import 'package:villager_translator/infrastructure/common/session_logger.dart';
import 'package:villager_translator/infrastructure/llm/llm_adapter_factory.dart';
import 'package:villager_translator/infrastructure/llm/mock_llm_adapter.dart';
import 'package:villager_translator/infrastructure/modtranslation/mod_translation_orchestrator.dart';

import '../../test_support/fake_jar_builder.dart';
import '../../test_support/in_memory_api_key_store.dart';
import '../../test_support/in_memory_settings_repository.dart';

class _FakeAdapterFactory implements LlmAdapterFactory {
  @override
  LlmAdapter create(LlmProvider provider, LlmAdapterConfig config) =>
      const MockLlmAdapter();
}

Future<SettingsController> _buildSettingsController() async {
  final controller = SettingsController(
    repository: InMemorySettingsRepository(),
    apiKeyStore: InMemoryApiKeyStore(),
  );
  await controller.load();
  return controller;
}

void main() {
  late Directory profileDir;
  late Directory appDir;

  setUp(() async {
    profileDir = await Directory.systemTemp.createTemp(
      'mod_controller_profile_test_',
    );
    appDir = await Directory.systemTemp.createTemp(
      'mod_controller_app_test_',
    );
  });

  tearDown(() async {
    if (await profileDir.exists()) {
      await profileDir.delete(recursive: true);
    }
    if (await appDir.exists()) {
      await appDir.delete(recursive: true);
    }
  });

  test(
    'プロファイルログには対象ファイル単位の粗いログのみ、アプリケーションログにはチャンク単位の詳細ログも記録される(Issue#10)',
    () async {
      await writeFakeJar(File(p.join(profileDir.path, 'mods', 'moda.jar')), {
        'fabric.mod.json': '{"id": "moda", "name": "Mod A", "version": "1.0"}',
        'assets/moda/lang/en_us.json': '{"item.a": "Item A"}',
      });

      final settingsController = await _buildSettingsController();
      final controller = ModTranslationController(
        settingsController: settingsController,
        orchestrator: ModTranslationOrchestrator(
          adapterFactory: _FakeAdapterFactory(),
        ),
        sessionIdGenerator: () => '20260805-000000',
        applicationSupportDirectory: appDir,
      );

      controller.setProfileDirectoryPath(profileDir.path);
      await controller.scan();
      controller.selectAll();
      await controller.translate();

      expect(controller.errorMessage, isNull);

      // メモリ上のリングバッファには詳細ログ(translate.chunk)も含まれる。
      expect(
        controller.sessionLogger.entries.any(
          (e) => e.category == 'translate.chunk',
        ),
        isTrue,
      );
      // 対象ファイル単位の粗いログ(translate.item)も記録される。
      final itemEntry = controller.sessionLogger.entries.firstWhere(
        (e) => e.category == 'translate.item',
      );
      expect(itemEntry.message, contains('Mod A'));
      expect(itemEntry.message, contains('成功'));
      expect(itemEntry.isMilestone, isTrue);

      final profileLogFile = File(
        p.joinAll([
          profileDir.path,
          'logs',
          'localizer',
          '20260805-000000',
          'session.log',
        ]),
      );
      final profileLines = await profileLogFile.readAsLines();
      final profileEntries = profileLines
          .map(LogEntry.tryParseLogLine)
          .whereType<LogEntry>()
          .toList();
      // プロファイルログには translate.chunk(詳細)は書き出されない。
      expect(
        profileEntries.any((e) => e.category == 'translate.chunk'),
        isFalse,
      );
      expect(
        profileEntries.any((e) => e.category == 'translate.item'),
        isTrue,
      );

      final appLogFile = File(
        p.joinAll([
          appDir.path,
          'logs',
          'localizer',
          '20260805-000000',
          'session.log',
        ]),
      );
      final appLines = await appLogFile.readAsLines();
      final appEntries = appLines
          .map(LogEntry.tryParseLogLine)
          .whereType<LogEntry>()
          .toList();
      // アプリケーションログには詳細ログ(translate.chunk)も書き出される。
      expect(appEntries.any((e) => e.category == 'translate.chunk'), isTrue);
      expect(appEntries.any((e) => e.category == 'translate.item'), isTrue);
    },
  );
}
