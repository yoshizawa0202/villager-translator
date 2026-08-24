import 'dart:io';

import 'package:path/path.dart' as p;

import '../../domain/minecraftinstance/launcher_metadata/atlauncher_metadata_parser.dart';
import '../../domain/minecraftinstance/minecraft_instance.dart';
import '../../domain/minecraftinstance/minecraft_launcher.dart';
import 'launcher_detector.dart';
import 'windows_environment.dart';

/// ATLauncher のインスタンスを検出する
/// (011-launcher-instance-discovery.md §8)。
///
/// Portable 版・カスタム保存先は、利用者が登録した追加パス
/// ([additionalRootPaths])をランチャールート候補として扱うことで対応する(§15.1)。
class ATLauncherDetector implements LauncherDetector {
  const ATLauncherDetector({
    required WindowsEnvironment environment,
    this.additionalRootPaths = const [],
  }) : _environment = environment;

  final WindowsEnvironment _environment;
  final List<String> additionalRootPaths;

  @override
  MinecraftLauncher get launcher => MinecraftLauncher.atLauncher;

  @override
  Future<List<MinecraftInstance>> discoverInstances() async {
    final instances = <MinecraftInstance>[];
    final seen = <String>{};

    for (final root in await _launcherRoots()) {
      final instancesDirectory = Directory(p.join(root.path, 'instances'));
      if (!await instancesDirectory.exists()) continue;
      if (!seen.add(instancesDirectory.path.toLowerCase())) continue;

      for (final directory in await listSubdirectories(instancesDirectory)) {
        final instance = await _buildInstance(directory);
        if (instance != null) instances.add(instance);
      }
    }
    return instances;
  }

  Future<List<Directory>> _launcherRoots() async {
    final roots = <Directory>[];

    final appData = _environment.appData;
    if (appData != null) {
      final standard = Directory(p.join(appData, 'ATLauncher'));
      if (await standard.exists()) roots.add(standard);
    }

    // 追加パス直下に `instances/` があれば ATLauncher 環境と判定する(§8、§15.1)。
    for (final path in additionalRootPaths) {
      final candidate = Directory(path);
      final names = (await listDirectChildNames(
        candidate,
      )).map((e) => e.toLowerCase()).toSet();
      if (names.contains('instances')) roots.add(candidate);
    }
    return roots;
  }

  Future<MinecraftInstance?> _buildInstance(Directory instanceFolder) async {
    final content = await readTextOrNull(
      File(p.join(instanceFolder.path, 'instance.json')),
    );
    if (content == null) return null;

    // ATLauncher のインスタンスフォルダは直下が Minecraft ルート(§8)。
    return buildInstanceFromDirectory(
      launcher: launcher,
      rootDirectory: instanceFolder,
      metadata: parseAtLauncherInstance(content),
      // `instance.json` が読めた場合は確定判定(§10)。
      confirmedByMetadata: true,
      fallbackName: p.basename(instanceFolder.path),
    );
  }
}
