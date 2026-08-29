import 'dart:io';

import 'package:path/path.dart' as p;

import '../../domain/minecraftinstance/launcher_metadata/instance_metadata.dart';
import '../../domain/minecraftinstance/launcher_metadata/prism_metadata_parser.dart';
import '../../domain/minecraftinstance/minecraft_instance.dart';
import '../../domain/minecraftinstance/minecraft_launcher.dart';
import 'launcher_detector.dart';
import 'windows_environment.dart';

/// Prism Launcher のインスタンスを検出する
/// (011-launcher-instance-discovery.md §6)。
///
/// Portable 版・カスタム Launcher Root は、利用者が登録した追加パス
/// ([additionalRootPaths])をランチャールート候補として扱うことで対応する(§15.1)。
class PrismLauncherDetector implements LauncherDetector {
  const PrismLauncherDetector({
    required WindowsEnvironment environment,
    this.additionalRootPaths = const [],
  }) : _environment = environment;

  final WindowsEnvironment _environment;

  /// 利用者が登録した追加パス(ランチャールート候補)。
  final List<String> additionalRootPaths;

  @override
  MinecraftLauncher get launcher => MinecraftLauncher.prism;

  @override
  Future<List<MinecraftInstance>> discoverInstances() async {
    final instances = <MinecraftInstance>[];
    for (final root in await _launcherRoots()) {
      instances.addAll(await _discoverInRoot(root));
    }
    return instances;
  }

  /// 標準パス → 登録済み追加パス の順にランチャールート候補を集める(§3)。
  Future<List<Directory>> _launcherRoots() async {
    final roots = <Directory>[];

    final appData = _environment.appData;
    if (appData != null) {
      final standard = Directory(p.join(appData, 'PrismLauncher'));
      if (await standard.exists()) roots.add(standard);
    }

    for (final path in additionalRootPaths) {
      final candidate = Directory(path);
      if (await _isPrismRoot(candidate)) roots.add(candidate);
    }
    return roots;
  }

  /// 追加パス直下に `prismlauncher.cfg` または `instances/` があれば Prism 環境
  /// と判定する(§6、§15.1)。
  Future<bool> _isPrismRoot(Directory directory) async {
    final names = (await listDirectChildNames(
      directory,
    )).map((e) => e.toLowerCase()).toSet();
    return names.contains('prismlauncher.cfg') || names.contains('instances');
  }

  Future<List<MinecraftInstance>> _discoverInRoot(Directory root) async {
    final instanceDirectory = await _resolveInstanceDirectory(root);
    if (!await instanceDirectory.exists()) return const [];

    final instances = <MinecraftInstance>[];
    for (final directory in await listSubdirectories(instanceDirectory)) {
      final instance = await _buildInstance(directory);
      if (instance != null) instances.add(instance);
    }
    return instances;
  }

  /// `prismlauncher.cfg` の `InstanceDir` を実際のインスタンス保存先として使う。
  /// 相対パスの場合はランチャールートからの相対として解決する(§6)。
  Future<Directory> _resolveInstanceDirectory(Directory root) async {
    final config = await readTextOrNull(
      File(p.join(root.path, 'prismlauncher.cfg')),
    );
    final instanceDir = config == null ? null : parsePrismInstanceDir(config);
    if (instanceDir == null) {
      return Directory(p.join(root.path, 'instances'));
    }
    return Directory(
      p.isAbsolute(instanceDir)
          ? instanceDir
          : p.normalize(p.join(root.path, instanceDir)),
    );
  }

  Future<MinecraftInstance?> _buildInstance(Directory instanceFolder) async {
    final instanceCfg = await readTextOrNull(
      File(p.join(instanceFolder.path, 'instance.cfg')),
    );
    final mmcPack = await readTextOrNull(
      File(p.join(instanceFolder.path, 'mmc-pack.json')),
    );

    // `instance.cfg` と `mmc-pack.json` の組が読めた場合は確定判定(§10)。
    final confirmed = instanceCfg != null && mmcPack != null;

    var metadata = instanceCfg == null
        ? InstanceMetadata.empty
        : parsePrismInstanceCfg(instanceCfg);
    if (mmcPack != null) {
      final pack = parseMmcPack(mmcPack);
      metadata = metadata.copyWith(
        minecraftVersion: pack.minecraftVersion,
        modLoader: pack.modLoader,
        modLoaderVersion: pack.modLoaderVersion,
      );
    }

    final minecraftRoot = await _resolveMinecraftRoot(instanceFolder);

    // `.minecraft` / `minecraft` のどちらも無くインスタンスフォルダ自体を
    // Minecraft ルート候補とする場合は、メタデータの有無に関わらずマーカー判定に
    // かける(§6)。ランチャー設定だけが残った空フォルダを拾わないため。
    final isFallbackRoot = minecraftRoot.path == instanceFolder.path;

    return buildInstanceFromDirectory(
      launcher: launcher,
      rootDirectory: minecraftRoot,
      metadata: metadata,
      confirmedByMetadata: confirmed && !isFallbackRoot,
      fallbackName: p.basename(instanceFolder.path),
    );
  }

  /// Minecraft ルートは `.minecraft` を優先し、存在しなければ `minecraft`
  /// (旧構成)を使う。どちらも存在しない場合はインスタンスフォルダ自体を
  /// 候補としてインスタンス検証にかける(§6)。
  Future<Directory> _resolveMinecraftRoot(Directory instanceFolder) async {
    for (final name in const ['.minecraft', 'minecraft']) {
      final candidate = Directory(p.join(instanceFolder.path, name));
      if (await candidate.exists()) return candidate;
    }
    return instanceFolder;
  }
}
