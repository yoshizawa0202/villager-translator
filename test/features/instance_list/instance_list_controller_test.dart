import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:villager_translator/domain/common/cancellation_token.dart';
import 'package:villager_translator/domain/minecraftinstance/minecraft_instance.dart';
import 'package:villager_translator/domain/minecraftinstance/minecraft_launcher.dart';
import 'package:villager_translator/features/instance_list/instance_list_controller.dart';
import 'package:villager_translator/infrastructure/minecraftinstance/instance_store.dart';
import 'package:villager_translator/infrastructure/minecraftinstance/launcher_detector.dart';
import 'package:villager_translator/infrastructure/minecraftinstance/launcher_discovery_service.dart';
import 'package:villager_translator/infrastructure/minecraftinstance/windows_environment.dart';

import '../../test_support/fake_instance_tree.dart';
import '../../test_support/fake_windows_environment.dart';

class _StubDetector implements LauncherDetector {
  _StubDetector(this.launcher, this.instances);

  @override
  final MinecraftLauncher launcher;

  final List<MinecraftInstance> instances;

  @override
  Future<List<MinecraftInstance>> discoverInstances() async => instances;
}

MinecraftInstance _instance(
  String name,
  String rootPath,
  MinecraftLauncher launcher,
) => MinecraftInstance(
  id: buildInstanceId(launcher, rootPath),
  name: name,
  launcher: launcher,
  rootPath: rootPath,
);

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('instance_list_test_');
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  String at(List<String> segments) => p.joinAll([tempDir.path, ...segments]);

  InstanceListController buildController({
    List<MinecraftInstance> instances = const [],
    InstanceStore? store,
    DeepInstanceSearch? deepSearch,
    List<String>? capturedManualPaths,
  }) {
    return InstanceListController(
      environment: const FakeWindowsEnvironment(),
      store: store,
      deepSearch: deepSearch,
      discoveryServiceFactory: (manualPaths) {
        capturedManualPaths
          ?..clear()
          ..addAll(manualPaths);
        return LauncherDiscoveryService(
          environment: const FakeWindowsEnvironment(),
          detectors: [_StubDetector(MinecraftLauncher.prism, instances)],
        );
      },
    );
  }

  test('ランチャー別フィルターとインスタンス名検索で絞り込む(011 AC-14)', () async {
    final controller = buildController(
      instances: [
        _instance('Prominence II', at(['a']), MinecraftLauncher.prism),
        _instance('Better MC', at(['b']), MinecraftLauncher.prism),
      ],
    );
    await controller.discover();

    expect(controller.visibleInstances, hasLength(2));

    controller.setSearchQuery('prom');
    expect(controller.visibleInstances.map((e) => e.name).toList(), [
      'Prominence II',
    ]);

    controller.setSearchQuery('PROM');
    expect(controller.visibleInstances, hasLength(1));

    controller.setSearchQuery('');
    controller.setLauncherFilter(MinecraftLauncher.curseForge);
    expect(controller.visibleInstances, isEmpty);

    controller.setLauncherFilter(null);
    expect(controller.visibleInstances, hasLength(2));
  });

  test('ランチャーごとに見出し用のグループへまとめる(011 §13)', () async {
    final controller = buildController(
      instances: [
        _instance('A', at(['a']), MinecraftLauncher.prism),
        _instance('B', at(['b']), MinecraftLauncher.prism),
      ],
    );
    await controller.discover();

    expect(controller.visibleByLauncher.keys.toList(), [
      MinecraftLauncher.prism,
    ]);
    expect(controller.visibleByLauncher[MinecraftLauncher.prism], hasLength(2));
  });

  test('MOD 件数は mods/*.jar のファイル数だけを数える(011 §13)', () async {
    await createInstanceMarkers(at(['pack']));
    await writeTextFile(at(['pack', 'mods', 'a.jar']), 'x');
    await writeTextFile(at(['pack', 'mods', 'b.jar']), 'x');
    await writeTextFile(at(['pack', 'mods', 'readme.txt']), 'x');

    final instance = _instance('Pack', at(['pack']), MinecraftLauncher.prism);
    final controller = buildController(instances: [instance]);
    await controller.discover();

    expect(controller.modJarCountOf(instance), 2);
  });

  test('手動追加パスが instances.json へ保存され、次回起動時にも検索対象になる(011 AC-16)', () async {
    await createInstanceMarkers(at(['custom', 'MyPack']));
    final store = InstanceStore.forApplicationSupportDirectory(tempDir);
    final captured = <String>[];

    final controller = buildController(
      store: store,
      capturedManualPaths: captured,
    );
    await controller.loadAndDiscover();

    final error = await controller.addManualPath(at(['custom', 'MyPack']));

    expect(error, isNull);
    expect(controller.manualPaths, hasLength(1));
    expect(captured, hasLength(1));
    expect((await store.load()).manualPaths, hasLength(1));

    // 再起動を模した別コントローラーでも読み込まれる。
    final reloaded = buildController(store: store);
    await reloaded.loadAndDiscover();
    expect(reloaded.manualPaths, hasLength(1));
  });

  test('インスタンスともランチャールートとも解釈できないパスは日本語エラーで登録されない(011 AC-16)', () async {
    await Directory(at(['empty'])).create(recursive: true);
    final controller = buildController();
    await controller.discover();

    expect(
      await controller.addManualPath(at(['empty'])),
      contains('認識できませんでした'),
    );
    expect(
      await controller.addManualPath(at(['missing'])),
      contains('見つかりません'),
    );
    expect(await controller.addManualPath('   '), contains('入力してください'));
    expect(controller.manualPaths, isEmpty);
  });

  test('同じパスを二重に追加しない', () async {
    await createInstanceMarkers(at(['custom', 'MyPack']));
    final controller = buildController();
    await controller.discover();

    expect(await controller.addManualPath(at(['custom', 'MyPack'])), isNull);
    expect(
      await controller.addManualPath(at(['custom', 'MyPack'])),
      contains('既に追加されています'),
    );
    expect(controller.manualPaths, hasLength(1));
  });

  test('詳細検索は検出 0 件のときだけ提示し、結果を一覧へ加える(011 AC-18)', () async {
    final found = _instance('Found', at(['found']), MinecraftLauncher.manual);
    var searched = false;

    final controller = buildController(
      deepSearch:
          ({
            required WindowsEnvironment environment,
            CancellationToken? cancellationToken,
            void Function(String path)? onDirectoryVisited,
          }) async {
            searched = true;
            onDirectoryVisited?.call(at(['scanning']));
            return [found];
          },
    );
    await controller.discover();

    expect(controller.canOfferDeepSearch, isTrue);

    await controller.deepSearch();

    expect(searched, isTrue);
    expect(controller.instances.map((e) => e.name).toList(), ['Found']);
    // 1 件でも見つかった後は詳細検索を提示しない。
    expect(controller.canOfferDeepSearch, isFalse);
  });

  test('最近使用は選択のたびに記録され、消えたインスタンスは「見つかりません」になる(011 AC-19)', () async {
    await createInstanceMarkers(at(['pack']));
    final instance = _instance('Pack', at(['pack']), MinecraftLauncher.prism);
    final store = InstanceStore.forApplicationSupportDirectory(tempDir);

    final controller = buildController(instances: [instance], store: store);
    await controller.loadAndDiscover();
    await controller.markInstanceUsed(instance);

    expect(controller.recentInstances.single.name, 'Pack');
    expect(
      controller.isRecentMissing(controller.recentInstances.single),
      isFalse,
    );

    await Directory(at(['pack'])).delete(recursive: true);

    // 再起動を模した別コントローラーでは、消えたパスが「見つかりません」になる。
    final reloaded = buildController(store: store);
    await reloaded.loadAndDiscover();
    final recent = reloaded.recentInstances.single;
    expect(reloaded.isRecentMissing(recent), isTrue);

    await reloaded.removeRecentInstance(recent.id);
    expect(reloaded.recentInstances, isEmpty);
    expect((await store.load()).recentInstances, isEmpty);
  });

  test('1 つの Detector が失敗しても一覧は表示され、日本語の警告が出る(011 AC-20)', () async {
    final controller = InstanceListController(
      environment: const FakeWindowsEnvironment(),
      discoveryServiceFactory: (_) => LauncherDiscoveryService(
        environment: const FakeWindowsEnvironment(),
        detectors: [_ThrowingDetector()],
      ),
    );

    await controller.discover();

    expect(controller.state, InstanceListState.discovered);
    expect(controller.errorMessage, contains('一部のランチャーを検出できませんでした'));
  });
}

/// 必ず例外を投げる Detector(011 AC-20)。
class _ThrowingDetector implements LauncherDetector {
  @override
  MinecraftLauncher get launcher => MinecraftLauncher.curseForge;

  @override
  Future<List<MinecraftInstance>> discoverInstances() async {
    throw const FormatException('設定ファイルが壊れています');
  }
}
