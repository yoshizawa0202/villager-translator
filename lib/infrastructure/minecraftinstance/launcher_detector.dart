import 'dart:io';

import 'package:path/path.dart' as p;

import '../../domain/minecraftinstance/instance_validator.dart';
import '../../domain/minecraftinstance/launcher_metadata/instance_metadata.dart';
import '../../domain/minecraftinstance/launcher_metadata/latest_log_parser.dart';
import '../../domain/minecraftinstance/minecraft_instance.dart';
import '../../domain/minecraftinstance/minecraft_launcher.dart';
import '../../domain/minecraftinstance/mod_loader.dart';

/// ランチャーごとの検出処理を束ねる共通インターフェース
/// (011-launcher-instance-discovery.md §2)。
///
/// 実装は自身の解析失敗を捕捉して空リストを返し、例外を呼び出し元へ伝播させない
/// (AC-20: 1つのランチャー設定ファイルが壊れていてもアプリ全体を止めない)。
abstract class LauncherDetector {
  MinecraftLauncher get launcher;

  Future<List<MinecraftInstance>> discoverInstances();
}

/// 正規化済み絶対パスを返す(§11)。
///
/// 1. 絶対パスへ解決する
/// 2. 可能なら `resolveSymbolicLinks()` を試み、失敗した場合は正規化のみで続行する
/// 3. 末尾のパスセパレータを除去する
///
/// 大文字小文字の非区別は比較時([deduplicateInstances])に行うため、ここでは
/// 表示に使える元の表記のまま残す。
Future<String> normalizeInstancePath(String path) async {
  final absolute = p.normalize(p.absolute(path));
  try {
    final resolved = await Directory(absolute).resolveSymbolicLinks();
    return _stripTrailingSeparator(p.normalize(resolved));
  } catch (_) {
    return _stripTrailingSeparator(absolute);
  }
}

String _stripTrailingSeparator(String path) {
  // ドライブルート(`C:\`)は末尾セパレータを外すとパスとして成立しないため残す。
  if (path.length <= 3) return path;
  var result = path;
  while (result.length > 3 &&
      (result.endsWith(p.separator) || result.endsWith('/'))) {
    result = result.substring(0, result.length - 1);
  }
  return result;
}

/// [directory] 直下のファイル・ディレクトリ名(basename)を集める。
///
/// 読み取れない場合(存在しない・アクセス権限が無い)は空集合を返し、例外を
/// 呼び出し元へ伝播させない。
Future<Set<String>> listDirectChildNames(Directory directory) async {
  try {
    if (!await directory.exists()) return const {};
    return await directory
        .list(followLinks: false)
        .map((entity) => p.basename(entity.path))
        .toSet();
  } catch (_) {
    return const {};
  }
}

/// [directory] 直下のサブディレクトリ一覧(名前昇順)。
///
/// 読み取れない場合は空リストを返す。
Future<List<Directory>> listSubdirectories(Directory directory) async {
  try {
    if (!await directory.exists()) return const [];
    final directories = await directory
        .list(followLinks: false)
        .where((entity) => entity is Directory)
        .cast<Directory>()
        .toList();
    directories.sort(
      (a, b) => p
          .basename(a.path)
          .toLowerCase()
          .compareTo(p.basename(b.path).toLowerCase()),
    );
    return directories;
  } catch (_) {
    return const [];
  }
}

/// マーカー判定(§10)を実ディレクトリに対して行う。
Future<bool> directoryLooksLikeInstance(Directory directory) async {
  return looksLikeMinecraftInstance(await listDirectChildNames(directory));
}

/// [file] のテキストを読む。存在しない・読めない場合は `null`(例外を投げない)。
Future<String?> readTextOrNull(File file) async {
  try {
    if (!await file.exists()) return null;
    return await file.readAsString();
  } catch (_) {
    return null;
  }
}

/// ランチャーメタデータで埋まらなかった項目を `logs/latest.log` から補完する
/// (§12 の第2段)。
///
/// JAR の読み取りを伴う第3段は一覧表示時には実行せず、インスタンス選択後の
/// 自動解析(§16)で補う。
Future<InstanceMetadata> completeFromLatestLog(
  Directory rootDirectory,
  InstanceMetadata metadata,
) async {
  if (metadata.minecraftVersion != null &&
      metadata.modLoader != ModLoader.unknown) {
    return metadata;
  }

  final content = await readTextOrNull(
    File(p.join(rootDirectory.path, 'logs', 'latest.log')),
  );
  if (content == null) return metadata;

  final hint = parseLatestLog(content);
  return metadata.copyWith(
    minecraftVersion: metadata.minecraftVersion ?? hint.minecraftVersion,
    modLoader: metadata.modLoader == ModLoader.unknown
        ? hint.modLoader
        : metadata.modLoader,
    modLoaderVersion: metadata.modLoaderVersion ?? hint.modLoaderVersion,
  );
}

/// 検出したディレクトリと読み取り済みメタデータから [MinecraftInstance] を組み立てる。
///
/// [confirmedByMetadata] が `true`(ランチャー固有メタデータを読み取れた)の
/// 場合はその 1 件だけで確定とし、マーカー判定を行わない(§10 の確定判定)。
/// `false` の場合はマーカー判定を満たさないディレクトリを除外し、`null` を返す。
Future<MinecraftInstance?> buildInstanceFromDirectory({
  required MinecraftLauncher launcher,
  required Directory rootDirectory,
  required InstanceMetadata metadata,
  required bool confirmedByMetadata,
  String? fallbackName,
}) async {
  if (!await rootDirectory.exists()) return null;
  if (!confirmedByMetadata &&
      !await directoryLooksLikeInstance(rootDirectory)) {
    return null;
  }

  final completed = await completeFromLatestLog(rootDirectory, metadata);
  final normalizedPath = await normalizeInstancePath(rootDirectory.path);

  return MinecraftInstance(
    id: buildInstanceId(launcher, normalizedPath),
    name: completed.name ?? fallbackName ?? p.basename(normalizedPath),
    launcher: launcher,
    rootPath: normalizedPath,
    minecraftVersion: completed.minecraftVersion,
    modLoader: completed.modLoader,
    modLoaderVersion: completed.modLoaderVersion,
    iconPath: completed.iconPath,
    lastPlayed: completed.lastPlayed,
  );
}
