import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:villager_translator/domain/minecraftinstance/minecraft_instance.dart';
import 'package:villager_translator/domain/minecraftinstance/minecraft_launcher.dart';
import 'package:villager_translator/domain/minecraftinstance/mod_loader.dart';
import 'package:villager_translator/infrastructure/minecraftinstance/launcher_detector.dart';
import 'package:villager_translator/infrastructure/minecraftinstance/launcher_discovery_service.dart';

import '../../test_support/fake_instance_tree.dart';
import '../../test_support/fake_windows_environment.dart';

/// 固定の結果を返す Detector。
class _StubDetector implements LauncherDetector {
  _StubDetector(this.launcher, this.instances);

  @override
  final MinecraftLauncher launcher;

  final List<MinecraftInstance> instances;

  @override
  Future<List<MinecraftInstance>> discoverInstances() async => instances;
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

MinecraftInstance _instance({
  required String name,
  required String rootPath,
  required MinecraftLauncher launcher,
  String? minecraftVersion,
  ModLoader modLoader = ModLoader.unknown,
  DateTime? lastPlayed,
}) => MinecraftInstance(
  id: buildInstanceId(launcher, rootPath),
  name: name,
  launcher: launcher,
  rootPath: rootPath,
  minecraftVersion: minecraftVersion,
  modLoader: modLoader,
  lastPlayed: lastPlayed,
);

void main() {
  test('全 Detector の結果を重複排除・整列して返す(011 AC-09、§14)', () async {
    final service = LauncherDiscoveryService(
      environment: const FakeWindowsEnvironment(),
      detectors: [
        _StubDetector(MinecraftLauncher.prism, [
          _instance(
            name: 'Shared',
            rootPath: 'D:/mc/shared',
            launcher: MinecraftLauncher.prism,
            minecraftVersion: '1.20.1',
            lastPlayed: DateTime(2026, 8, 1),
          ),
        ]),
        _StubDetector(MinecraftLauncher.manual, [
          _instance(
            name: 'Shared',
            rootPath: 'd:/MC/Shared',
            launcher: MinecraftLauncher.manual,
            modLoader: ModLoader.fabric,
          ),
          _instance(
            name: 'Another',
            rootPath: 'D:/mc/another',
            launcher: MinecraftLauncher.manual,
          ),
        ]),
      ],
    );

    final instances = await service.discoverAll();

    expect(instances, hasLength(2));
    // lastPlayed のある Shared が先頭、無い Another が末尾。
    expect(instances.first.name, 'Shared');
    expect(instances.first.launcher, MinecraftLauncher.prism);
    // メタデータがより充実している側の値が採用される。
    expect(instances.first.minecraftVersion, '1.20.1');
    expect(instances.first.modLoader, ModLoader.fabric);
  });

  test('1 つの Detector が例外を投げても他の検出は継続する(011 AC-20)', () async {
    final failures = <String>[];
    final service = LauncherDiscoveryService(
      environment: const FakeWindowsEnvironment(),
      detectors: [
        _ThrowingDetector(),
        _StubDetector(MinecraftLauncher.prism, [
          _instance(
            name: 'Alive',
            rootPath: 'D:/mc/alive',
            launcher: MinecraftLauncher.prism,
          ),
        ]),
      ],
    );

    final instances = await service.discoverAll(
      onDetectorError: (detector, error) =>
          failures.add(detector.launcher.name),
    );

    expect(instances.map((e) => e.name).toList(), ['Alive']);
    expect(failures, ['curseForge']);
  });

  test('既定の Detector は 6 種類で、標準パスのみを検索する(011 AC-07)', () async {
    final tempDir = await Directory.systemTemp.createTemp('discovery_test_');
    addTearDown(() async {
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });

    // 標準パスの外(ドライブ直下の深い場所)に置いたインスタンスは、
    // 既定の検出では拾わない(全ドライブ再帰検索を行わないため)。
    await createInstanceMarkers(
      p.join(tempDir.path, 'somewhere', 'deep', 'mc'),
    );

    final service = LauncherDiscoveryService(
      environment: FakeWindowsEnvironment(
        appData: p.join(tempDir.path, 'appdata'),
        userProfile: p.join(tempDir.path, 'user'),
        driveRoots: [tempDir.path],
      ),
    );

    expect(service.detectors, hasLength(6));
    expect(await service.discoverAll(), isEmpty);
  });
}
