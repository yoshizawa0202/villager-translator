import 'dart:io';

import '../../domain/minecraftinstance/launcher_metadata/instance_metadata.dart';
import '../../domain/minecraftinstance/minecraft_instance.dart';
import '../../domain/minecraftinstance/minecraft_launcher.dart';
import 'launcher_detector.dart';

/// 利用者が手動で追加したパスのうち、それ自体がインスタンス検証を満たすものを
/// [MinecraftLauncher.manual] のインスタンスとして登録する
/// (011-launcher-instance-discovery.md §15.1)。
///
/// 追加パスがランチャールート(`instances/` `profiles/` `prismlauncher.cfg` を
/// 含むディレクトリ)である場合の配下検出は、各ランチャー Detector が
/// `additionalRootPaths` として受け取って行う。
class ManualInstanceDetector implements LauncherDetector {
  const ManualInstanceDetector({this.paths = const []});

  final List<String> paths;

  @override
  MinecraftLauncher get launcher => MinecraftLauncher.manual;

  @override
  Future<List<MinecraftInstance>> discoverInstances() async {
    final instances = <MinecraftInstance>[];
    for (final path in paths) {
      final instance = await buildInstanceFromDirectory(
        launcher: launcher,
        rootDirectory: Directory(path),
        metadata: InstanceMetadata.empty,
        confirmedByMetadata: false,
      );
      if (instance != null) instances.add(instance);
    }
    return instances;
  }
}
