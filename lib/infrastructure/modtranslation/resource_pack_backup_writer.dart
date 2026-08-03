import 'dart:io';

import 'package:path/path.dart' as p;

/// 生成したリソースパック([packDirectory])を、セッションディレクトリ配下の
/// バックアップ先(`{プロファイル}/logs/localizer/{sessionId}/backup/resource_pack/`)
/// へコピーする(feature-spec.md §6.2)。
Future<Directory> backupResourcePack({
  required Directory profileDirectory,
  required Directory packDirectory,
  required String sessionId,
}) async {
  final backupDirectory = Directory(
    p.join(
      profileDirectory.path,
      'logs',
      'localizer',
      sessionId,
      'backup',
      'resource_pack',
    ),
  );
  await backupDirectory.create(recursive: true);
  await _copyDirectoryContents(packDirectory, backupDirectory);
  return backupDirectory;
}

Future<void> _copyDirectoryContents(
  Directory source,
  Directory destination,
) async {
  await for (final entity in source.list()) {
    final name = p.basename(entity.path);
    if (entity is Directory) {
      final childDestination = Directory(p.join(destination.path, name));
      await childDestination.create(recursive: true);
      await _copyDirectoryContents(entity, childDestination);
    } else if (entity is File) {
      await entity.copy(p.join(destination.path, name));
    }
  }
}
