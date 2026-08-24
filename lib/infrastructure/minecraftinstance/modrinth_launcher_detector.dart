import 'dart:io';

import 'package:path/path.dart' as p;

import '../../domain/minecraftinstance/launcher_metadata/instance_metadata.dart';
import '../../domain/minecraftinstance/minecraft_instance.dart';
import '../../domain/minecraftinstance/minecraft_launcher.dart';
import 'launcher_detector.dart';
import 'windows_environment.dart';

/// Modrinth App のプロファイルを検出する
/// (011-launcher-instance-discovery.md §9)。
///
/// Modrinth App はインスタンス構成を SQLite データベース(`app.db`)に持つが、
/// 本実装はこれを読まない(設計判断: ネイティブ依存の追加と非公開スキーマへの
/// 依存を避ける)。`profiles/` 配下のディレクトリ列挙とインスタンス検証、
/// メタデータ多段フォールバックのみで検出する(AC-05)。
class ModrinthLauncherDetector implements LauncherDetector {
  const ModrinthLauncherDetector({
    required WindowsEnvironment environment,
    this.additionalRootPaths = const [],
  }) : _environment = environment;

  final WindowsEnvironment _environment;
  final List<String> additionalRootPaths;

  /// `%APPDATA%` 直下のデータディレクトリ名(旧バージョン互換を含む、§9)。
  static const List<String> dataDirectoryNames = [
    'ModrinthApp',
    'com.modrinth.theseus',
  ];

  @override
  MinecraftLauncher get launcher => MinecraftLauncher.modrinth;

  @override
  Future<List<MinecraftInstance>> discoverInstances() async {
    final instances = <MinecraftInstance>[];
    final seen = <String>{};

    for (final root in await _launcherRoots()) {
      final profiles = Directory(p.join(root.path, 'profiles'));
      if (!await profiles.exists()) continue;
      if (!seen.add(profiles.path.toLowerCase())) continue;

      for (final directory in await listSubdirectories(profiles)) {
        // メタデータが無いため、マーカー判定でインスタンスかどうかを決める(§10)。
        final instance = await buildInstanceFromDirectory(
          launcher: launcher,
          // Modrinth のプロファイルフォルダは直下が Minecraft ルート(§9)。
          rootDirectory: directory,
          metadata: InstanceMetadata(name: p.basename(directory.path)),
          confirmedByMetadata: false,
        );
        if (instance != null) instances.add(instance);
      }
    }
    return instances;
  }

  Future<List<Directory>> _launcherRoots() async {
    final roots = <Directory>[];

    final appData = _environment.appData;
    if (appData != null) {
      for (final name in dataDirectoryNames) {
        final candidate = Directory(p.join(appData, name));
        if (await candidate.exists()) roots.add(candidate);
      }
    }

    // 追加パス直下に `profiles/` があれば Modrinth 環境と判定する(§9、§15.1)。
    for (final path in additionalRootPaths) {
      final candidate = Directory(path);
      final names = (await listDirectChildNames(
        candidate,
      )).map((e) => e.toLowerCase()).toSet();
      if (names.contains('profiles')) roots.add(candidate);
    }
    return roots;
  }
}
