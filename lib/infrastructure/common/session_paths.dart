import 'dart:io';

import 'package:path/path.dart' as p;

/// `{プロファイル}/logs/localizer/` 配下のディレクトリ規約
/// (feature-spec.md §1.4)の単一の真実源。
Directory localizerLogsDirectory(Directory profileDirectory) =>
    Directory(p.join(profileDirectory.path, 'logs', 'localizer'));

/// 1回の翻訳実行(セッション)に紐づくパス群
/// (`{プロファイル}/logs/localizer/{sessionId}/...`、feature-spec.md §1.4)。
class SessionPaths {
  SessionPaths({required this.profileDirectory, required this.sessionId});

  final Directory profileDirectory;
  final String sessionId;

  /// `{プロファイル}/logs/localizer/{sessionId}/`
  Directory get sessionDirectory => Directory(
    p.join(localizerLogsDirectory(profileDirectory).path, sessionId),
  );

  /// `.../backup/`
  Directory get backupDirectory =>
      Directory(p.join(sessionDirectory.path, 'backup'));

  /// `.../backup/{name}/`(例: `resource_pack`、`snbt_original`、`patchouli_jar`)
  Directory backupSubdirectory(String name) =>
      Directory(p.join(backupDirectory.path, name));

  /// `.../session.log`
  File get logFile => File(p.join(sessionDirectory.path, 'session.log'));

  /// `.../translation_summary.json`
  File get summaryFile =>
      File(p.join(sessionDirectory.path, 'translation_summary.json'));
}
