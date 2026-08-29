import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:villager_translator/domain/minecraftinstance/minecraft_instance.dart';
import 'package:villager_translator/domain/minecraftinstance/minecraft_launcher.dart';
import 'package:villager_translator/domain/minecraftinstance/mod_loader.dart';
import 'package:villager_translator/features/instance_list/instance_list_controller.dart';
import 'package:villager_translator/features/instance_list/instance_list_page.dart';
import 'package:villager_translator/features/settings/settings_controller.dart';
import 'package:villager_translator/infrastructure/minecraftinstance/launcher_detector.dart';
import 'package:villager_translator/infrastructure/minecraftinstance/launcher_discovery_service.dart';

import '../../test_support/fake_instance_tree.dart';
import '../../test_support/fake_windows_environment.dart';
import '../../test_support/in_memory_api_key_store.dart';
import '../../test_support/in_memory_settings_repository.dart';

class _StubDetector implements LauncherDetector {
  _StubDetector(this.instances);

  @override
  MinecraftLauncher get launcher => MinecraftLauncher.prism;

  final List<MinecraftInstance> instances;

  @override
  Future<List<MinecraftInstance>> discoverInstances() async => instances;
}

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('instance_list_page_test_');
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  Future<InstanceListController> pumpPage(
    WidgetTester tester,
    List<MinecraftInstance> instances,
  ) async {
    final settingsController = SettingsController(
      repository: InMemorySettingsRepository(),
      apiKeyStore: InMemoryApiKeyStore(),
    );
    await settingsController.load();

    final controller = InstanceListController(
      environment: const FakeWindowsEnvironment(),
      discoveryServiceFactory: (_) => LauncherDiscoveryService(
        environment: const FakeWindowsEnvironment(),
        detectors: [_StubDetector(instances)],
      ),
    );
    await tester.runAsync(controller.discover);

    await tester.pumpWidget(
      ChangeNotifierProvider<SettingsController>.value(
        value: settingsController,
        child: MaterialApp(home: InstanceListPage(controller: controller)),
      ),
    );
    await tester.pumpAndSettle();
    return controller;
  }

  testWidgets('一覧にランチャー見出し・名前・バージョン・Loader・MOD 件数が表示される(011 AC-13)', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await createInstanceMarkers(p.join(tempDir.path, 'pack'));
      await writeTextFile(p.join(tempDir.path, 'pack', 'mods', 'a.jar'), 'x');
    });

    final instance = MinecraftInstance(
      id: 'test-instance',
      name: 'Prominence II',
      launcher: MinecraftLauncher.prism,
      rootPath: p.join(tempDir.path, 'pack'),
      minecraftVersion: '1.20.1',
      modLoader: ModLoader.fabric,
    );

    await pumpPage(tester, [instance]);

    expect(find.byKey(const Key('launcherHeading_prism')), findsOneWidget);
    expect(find.byKey(const Key('instanceCard_test-instance')), findsOneWidget);
    expect(find.text('Prominence II'), findsOneWidget);
    expect(
      find.textContaining('Minecraft 1.20.1 / Fabric / MOD 1 個'),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('translateInstanceButton_test-instance')),
      findsOneWidget,
    );
  });

  testWidgets('検索欄でインスタンス名を絞り込める(011 AC-14)', (tester) async {
    final controller = await pumpPage(tester, [
      MinecraftInstance(
        id: 'a',
        name: 'Prominence II',
        launcher: MinecraftLauncher.prism,
        rootPath: p.join(tempDir.path, 'a'),
      ),
      MinecraftInstance(
        id: 'b',
        name: 'Better MC',
        launcher: MinecraftLauncher.prism,
        rootPath: p.join(tempDir.path, 'b'),
      ),
    ]);

    await tester.enterText(
      find.byKey(const Key('instanceSearchField')),
      'better',
    );
    await tester.pumpAndSettle();

    expect(controller.visibleInstances.map((e) => e.name).toList(), [
      'Better MC',
    ]);
    expect(find.byKey(const Key('instanceCard_a')), findsNothing);
    expect(find.byKey(const Key('instanceCard_b')), findsOneWidget);
  });

  testWidgets('検出 0 件のときだけ「PC内を詳しく検索」を提示する(011 AC-18)', (tester) async {
    await pumpPage(tester, const []);

    expect(find.byKey(const Key('instanceListEmptyState')), findsOneWidget);
    expect(find.byKey(const Key('deepSearchButton')), findsOneWidget);
  });
}
