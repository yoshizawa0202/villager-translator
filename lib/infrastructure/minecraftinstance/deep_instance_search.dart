import 'dart:io';

import 'package:path/path.dart' as p;

import '../../domain/common/cancellation_token.dart';
import '../../domain/minecraftinstance/instance_deduplicator.dart';
import '../../domain/minecraftinstance/instance_validator.dart';
import '../../domain/minecraftinstance/launcher_metadata/instance_metadata.dart';
import '../../domain/minecraftinstance/minecraft_instance.dart';
import '../../domain/minecraftinstance/minecraft_launcher.dart';
import 'launcher_detector.dart';
import 'windows_environment.dart';

/// 詳細検索のルートからの深さ上限(011-launcher-instance-discovery.md §15.3)。
const int kDeepSearchDefaultMaxDepth = 6;

/// 詳細検索で降りない既定の除外ディレクトリ(§15.3)。比較は大文字小文字を区別しない。
const List<String> kDeepSearchExcludedDirectoryNames = [
  'Windows',
  'Program Files',
  'Program Files (x86)',
  'ProgramData',
  r'$Recycle.Bin',
  'System Volume Information',
  'node_modules',
  '.git',
];

/// 全固定ドライブのルートから再帰探索して Minecraft インスタンスを探す(§15.3)。
///
/// 自動検出で 1 件も見つからなかった場合にのみ、利用者の明示的な操作で実行する。
/// 深さ上限と除外ディレクトリに従い、インスタンスと判定したディレクトリ配下へは
/// それ以上降りない。アクセス権限エラーはそのディレクトリのみスキップし、
/// 探索全体を中断しない(AC-18)。
Future<List<MinecraftInstance>> searchInstancesDeeply({
  required WindowsEnvironment environment,
  int maxDepth = kDeepSearchDefaultMaxDepth,
  CancellationToken? cancellationToken,
  void Function(String path)? onDirectoryVisited,
}) async {
  final excluded = kDeepSearchExcludedDirectoryNames
      .map((e) => e.toLowerCase())
      .toSet();
  final found = <MinecraftInstance>[];

  for (final root in await environment.fixedDriveRoots()) {
    if (cancellationToken?.isCancelled ?? false) break;
    await _searchDirectory(
      directory: Directory(root),
      depth: 0,
      maxDepth: maxDepth,
      excludedNames: excluded,
      cancellationToken: cancellationToken,
      onDirectoryVisited: onDirectoryVisited,
      found: found,
    );
  }

  return sortInstancesForDisplay(deduplicateInstances(found));
}

Future<void> _searchDirectory({
  required Directory directory,
  required int depth,
  required int maxDepth,
  required Set<String> excludedNames,
  required CancellationToken? cancellationToken,
  required void Function(String path)? onDirectoryVisited,
  required List<MinecraftInstance> found,
}) async {
  if (cancellationToken?.isCancelled ?? false) return;
  if (depth > maxDepth) return;

  onDirectoryVisited?.call(directory.path);

  final childNames = await listDirectChildNames(directory);
  if (childNames.isEmpty) return;

  if (looksLikeMinecraftInstance(childNames)) {
    final instance = await buildInstanceFromDirectory(
      launcher: MinecraftLauncher.manual,
      rootDirectory: directory,
      metadata: InstanceMetadata.empty,
      confirmedByMetadata: true,
      fallbackName: p.basename(directory.path),
    );
    if (instance != null) found.add(instance);
    // インスタンスと判定したディレクトリ配下へはそれ以上降りない(§15.3)。
    return;
  }

  if (depth == maxDepth) return;

  for (final child in await listSubdirectories(directory)) {
    if (cancellationToken?.isCancelled ?? false) return;
    if (excludedNames.contains(p.basename(child.path).toLowerCase())) continue;

    await _searchDirectory(
      directory: child,
      depth: depth + 1,
      maxDepth: maxDepth,
      excludedNames: excludedNames,
      cancellationToken: cancellationToken,
      onDirectoryVisited: onDirectoryVisited,
      found: found,
    );
  }
}
