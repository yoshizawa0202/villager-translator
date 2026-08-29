import 'dart:io';

import 'package:path/path.dart' as p;

import '../../domain/common/cancellation_token.dart';
import '../../domain/minecraftinstance/instance_analysis.dart';
import '../../domain/minecraftinstance/launcher_metadata/instance_metadata.dart';
import '../../domain/minecraftinstance/launcher_metadata/mod_jar_version_hint.dart';
import '../../domain/minecraftinstance/minecraft_instance.dart';
import '../../domain/minecraftinstance/mod_loader.dart';
import '../../domain/modtranslation/jar_contents.dart';
import '../modtranslation/jar_reader.dart';
import '../modtranslation/mod_directory_scanner.dart';
import '../patchoulitranslation/patchouli_directory_scanner.dart';
import '../questtranslation/quest_directory_scanner.dart';
import 'mod_jar_counter.dart';

/// 解析対象のインスタンスが既に存在しない場合に投げる例外(§16)。
class InstanceNotFoundException implements Exception {
  const InstanceNotFoundException(this.rootPath);

  final String rootPath;

  @override
  String toString() => 'インスタンスのフォルダが見つかりません: $rootPath';
}

/// 解析の進捗段階(§16: 解析は時間がかかるため進捗表示に対応する)。
enum InstanceAnalysisStage { mods, quests, guidebooks }

/// インスタンス選択後の自動解析(011-launcher-instance-discovery.md §16)。
///
/// 既存の 3 スキャナをそのまま再利用し、新しいスキャン処理は追加しない。
/// あわせて、ランチャーメタデータで埋まらなかった Minecraft バージョン・
/// Mod Loader を、既に読み込んだ MOD の JAR から補完する(§12 の第3段)。
class InstanceAnalyzer {
  const InstanceAnalyzer();

  Future<InstanceAnalysis> analyze({
    required MinecraftInstance instance,
    required String targetLanguageId,
    CancellationToken? cancellationToken,
    void Function(InstanceAnalysisStage stage)? onStageStarted,
  }) async {
    final rootDirectory = Directory(instance.rootPath);
    if (!await rootDirectory.exists()) {
      throw InstanceNotFoundException(instance.rootPath);
    }

    onStageStarted?.call(InstanceAnalysisStage.mods);
    final modJarCount = await countModJarFiles(rootDirectory);
    final modScan = await scanModsDirectory(
      profileDirectory: rootDirectory,
      targetLanguageId: targetLanguageId,
    );

    if (cancellationToken?.isCancelled ?? false) {
      return InstanceAnalysis(
        instance: instance,
        modJarCount: modJarCount,
        mods: modScan.entries,
        quests: const [],
        guidebooks: const [],
      );
    }

    onStageStarted?.call(InstanceAnalysisStage.quests);
    final quests = await scanQuestsDirectory(profileDirectory: rootDirectory);

    if (cancellationToken?.isCancelled ?? false) {
      return InstanceAnalysis(
        instance: instance,
        modJarCount: modJarCount,
        mods: modScan.entries,
        quests: quests,
        guidebooks: const [],
      );
    }

    onStageStarted?.call(InstanceAnalysisStage.guidebooks);
    final patchouli = await scanPatchouliBooksDirectory(
      profileDirectory: rootDirectory,
      targetLanguageId: targetLanguageId,
    );

    return InstanceAnalysis(
      instance: await _completeVersionFromMods(instance, rootDirectory),
      modJarCount: modJarCount,
      mods: modScan.entries,
      quests: quests,
      guidebooks: patchouli.entries,
    );
  }

  /// Minecraft バージョン・Mod Loader を `mods/` 内の JAR から推定して補う
  /// (§12 の第3段)。既に確定している項目は上書きしない。
  Future<MinecraftInstance> _completeVersionFromMods(
    MinecraftInstance instance,
    Directory rootDirectory,
  ) async {
    if (instance.minecraftVersion != null &&
        instance.modLoader != ModLoader.unknown) {
      return instance;
    }

    final hint = await _hintFromModJars(rootDirectory);
    if (hint.isEmpty) return instance;

    return instance.copyWith(
      minecraftVersion: instance.minecraftVersion ?? hint.minecraftVersion,
      modLoader: instance.modLoader == ModLoader.unknown
          ? hint.modLoader
          : instance.modLoader,
    );
  }

  Future<InstanceMetadata> _hintFromModJars(Directory rootDirectory) async {
    final modsDirectory = Directory(p.join(rootDirectory.path, 'mods'));
    if (!await modsDirectory.exists()) return InstanceMetadata.empty;

    final List<File> jarFiles;
    try {
      jarFiles = await modsDirectory
          .list(followLinks: false)
          .where(
            (entity) =>
                entity is File &&
                p.extension(entity.path).toLowerCase() == '.jar',
          )
          .cast<File>()
          .toList();
    } catch (_) {
      return InstanceMetadata.empty;
    }
    jarFiles.sort((a, b) => p.basename(a.path).compareTo(p.basename(b.path)));

    for (final jarFile in jarFiles) {
      final JarContents jar;
      try {
        jar = await readJarContents(jarFile);
      } catch (_) {
        continue; // 壊れた JAR は読み飛ばし、推定を継続する。
      }

      final fabricModJson = readJarText(jar, 'fabric.mod.json');
      if (fabricModJson != null) {
        final hint = hintFromFabricModJson(fabricModJson);
        if (hint.minecraftVersion != null) return hint;
      }

      final modsToml =
          readJarText(jar, 'META-INF/mods.toml') ??
          readJarText(jar, 'META-INF/neoforge.mods.toml');
      if (modsToml != null) {
        final hint = hintFromModsToml(modsToml);
        if (hint.minecraftVersion != null) return hint;
      }
    }
    return InstanceMetadata.empty;
  }
}
