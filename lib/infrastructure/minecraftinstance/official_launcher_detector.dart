import 'dart:io';

import 'package:path/path.dart' as p;

import '../../domain/minecraftinstance/launcher_metadata/instance_metadata.dart';
import '../../domain/minecraftinstance/launcher_metadata/launcher_profiles_parser.dart';
import '../../domain/minecraftinstance/minecraft_instance.dart';
import '../../domain/minecraftinstance/minecraft_launcher.dart';
import 'launcher_detector.dart';
import 'windows_environment.dart';

/// 公式 Minecraft Launcher のインスタンスを検出する
/// (011-launcher-instance-discovery.md §5)。
class OfficialLauncherDetector implements LauncherDetector {
  const OfficialLauncherDetector({required WindowsEnvironment environment})
    : _environment = environment;

  final WindowsEnvironment _environment;

  /// 解析対象のランチャー設定ファイル(§5)。
  static const List<String> profileFileNames = [
    'launcher_profiles.json',
    'launcher_profiles_microsoft_store.json',
  ];

  @override
  MinecraftLauncher get launcher => MinecraftLauncher.official;

  @override
  Future<List<MinecraftInstance>> discoverInstances() async {
    final appData = _environment.appData;
    if (appData == null) return const [];

    final defaultRoot = Directory(p.join(appData, '.minecraft'));
    if (!await defaultRoot.exists()) return const [];

    final instances = <MinecraftInstance>[];

    // Installation ごとのインスタンス(`gameDir` があればそのディレクトリ)。
    for (final fileName in profileFileNames) {
      final content = await readTextOrNull(
        File(p.join(defaultRoot.path, fileName)),
      );
      if (content == null) continue;

      for (final profile in parseLauncherProfiles(content)) {
        final rootDirectory = profile.metadata.gameDirectory != null
            ? Directory(profile.metadata.gameDirectory!)
            : defaultRoot;

        final instance = await buildInstanceFromDirectory(
          launcher: launcher,
          rootDirectory: rootDirectory,
          metadata: profile.metadata,
          // `launcher_profiles.json` の Installation エントリは確定判定(§10)。
          confirmedByMetadata: true,
          fallbackName: profile.key,
        );
        if (instance != null) instances.add(instance);
      }
    }

    // Installation を1件も読み取れなかった場合でも、`.minecraft` 自体が
    // インスタンスとして成立していれば検出する(マーカー判定、§10)。
    final base = await buildInstanceFromDirectory(
      launcher: launcher,
      rootDirectory: defaultRoot,
      metadata: InstanceMetadata.empty,
      confirmedByMetadata: false,
      fallbackName: 'Minecraft',
    );
    if (base != null) instances.add(base);

    return instances;
  }
}
