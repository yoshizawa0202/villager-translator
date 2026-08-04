import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:villager_translator/infrastructure/common/session_paths.dart';

void main() {
  test('SessionPaths が feature-spec.md §1.4 の規約通りのパスを組み立てる', () {
    final profileDirectory = Directory(p.join('C:', 'profile'));
    final paths = SessionPaths(
      profileDirectory: profileDirectory,
      sessionId: '2026-08-04T12-00-00',
    );

    expect(
      paths.sessionDirectory.path,
      p.joinAll([
        profileDirectory.path,
        'logs',
        'localizer',
        '2026-08-04T12-00-00',
      ]),
    );
    expect(
      paths.backupDirectory.path,
      p.join(paths.sessionDirectory.path, 'backup'),
    );
    expect(
      paths.backupSubdirectory('resource_pack').path,
      p.joinAll([paths.sessionDirectory.path, 'backup', 'resource_pack']),
    );
    expect(
      paths.logFile.path,
      p.join(paths.sessionDirectory.path, 'session.log'),
    );
    expect(
      paths.summaryFile.path,
      p.join(paths.sessionDirectory.path, 'translation_summary.json'),
    );
  });

  test('localizerLogsDirectory がプロファイル直下の logs/localizer を指す', () {
    final profileDirectory = Directory(p.join('C:', 'profile'));
    expect(
      localizerLogsDirectory(profileDirectory).path,
      p.joinAll([profileDirectory.path, 'logs', 'localizer']),
    );
  });
}
