import 'dart:io';

import 'package:path/path.dart' as p;

import '../../domain/minecraftinstance/launcher_metadata/curseforge_metadata_parser.dart';
import '../../domain/minecraftinstance/launcher_metadata/curseforge_settings_parser.dart';
import '../../domain/minecraftinstance/minecraft_instance.dart';
import '../../domain/minecraftinstance/minecraft_launcher.dart';
import 'launcher_detector.dart';
import 'windows_environment.dart';

/// CurseForge のインスタンスを検出する
/// (011-launcher-instance-discovery.md §7)。
///
/// CurseForge は Modding Folder を変更できるため、標準パスだけに依存しない。
/// 設定から取得できる場合はそれを優先し、取得できない場合は標準パスへ
/// フォールバックする(AC-03)。
class CurseForgeLauncherDetector implements LauncherDetector {
  const CurseForgeLauncherDetector({
    required WindowsEnvironment environment,
    this.additionalRootPaths = const [],
  }) : _environment = environment;

  final WindowsEnvironment _environment;

  /// 利用者が登録した追加パス(Modding Folder 候補)。
  final List<String> additionalRootPaths;

  /// 設定ファイルの探索先(「要検証項目」: ファイル名・キー名は未確定)。
  static const List<List<String>> settingsFileCandidates = [
    ['CurseForge', 'Settings', 'settings.json'],
    ['CurseForge', 'settings.json'],
  ];

  @override
  MinecraftLauncher get launcher => MinecraftLauncher.curseForge;

  @override
  Future<List<MinecraftInstance>> discoverInstances() async {
    final instances = <MinecraftInstance>[];
    final seen = <String>{};

    for (final moddingFolder in await _moddingFolders()) {
      final instancesDirectory = Directory(
        p.join(moddingFolder.path, 'Instances'),
      );
      final target = await instancesDirectory.exists()
          ? instancesDirectory
          : moddingFolder;
      if (!seen.add(target.path.toLowerCase())) continue;

      for (final directory in await listSubdirectories(target)) {
        final instance = await _buildInstance(directory);
        if (instance != null) instances.add(instance);
      }
    }
    return instances;
  }

  /// 設定から取得した Modding Folder → 標準パス → 登録済み追加パス の順に集める。
  Future<List<Directory>> _moddingFolders() async {
    final folders = <Directory>[];

    final configured = await _configuredModdingFolder();
    if (configured != null) folders.add(configured);

    final userProfile = _environment.userProfile;
    if (userProfile != null) {
      final standard = Directory(
        p.join(userProfile, 'curseforge', 'minecraft'),
      );
      if (await standard.exists()) folders.add(standard);
    }

    for (final path in additionalRootPaths) {
      final candidate = Directory(path);
      final names = (await listDirectChildNames(
        candidate,
      )).map((e) => e.toLowerCase()).toSet();
      if (names.contains('instances')) folders.add(candidate);
    }
    return folders;
  }

  Future<Directory?> _configuredModdingFolder() async {
    final appData = _environment.appData;
    if (appData == null) return null;

    for (final segments in settingsFileCandidates) {
      final content = await readTextOrNull(
        File(p.join(appData, p.joinAll(segments))),
      );
      if (content == null) continue;

      final folder = parseCurseForgeModdingFolder(content);
      if (folder == null) continue;

      final directory = Directory(folder);
      if (await directory.exists()) return directory;
    }
    return null;
  }

  Future<MinecraftInstance?> _buildInstance(Directory instanceFolder) async {
    final content = await readTextOrNull(
      File(p.join(instanceFolder.path, 'minecraftinstance.json')),
    );
    if (content == null) return null;

    // CurseForge のインスタンスフォルダは直下が Minecraft ルート(§7)。
    return buildInstanceFromDirectory(
      launcher: launcher,
      rootDirectory: instanceFolder,
      metadata: parseCurseForgeInstance(content),
      // `minecraftinstance.json` が読めた場合は確定判定(§10)。
      confirmedByMetadata: true,
      fallbackName: p.basename(instanceFolder.path),
    );
  }
}
