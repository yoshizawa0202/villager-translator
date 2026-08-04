import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:villager_translator/domain/common/translation_summary.dart';
import 'package:villager_translator/infrastructure/common/history_repository.dart';
import 'package:villager_translator/infrastructure/common/session_logger.dart';
import 'package:villager_translator/infrastructure/common/session_paths.dart';
import 'package:villager_translator/infrastructure/common/translation_summary_writer.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('history_repository_test_');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('セッション一覧を日時降順(セッションID降順)で返す', () async {
    const olderId = '2026-08-01T10-00-00';
    const newerId = '2026-08-02T10-00-00';

    for (final id in [olderId, newerId]) {
      await const TranslationSummaryWriter().write(
        profileDirectory: tempDir,
        summary: TranslationSummary(
          sessionId: id,
          targetLanguage: 'ja_jp',
          createdAt: DateTime(2026, 8, 1),
          items: const [],
        ),
      );
    }

    final sessions = await const HistoryRepository().listSessions(
      localizerLogsDirectory(tempDir),
    );

    expect(sessions.map((s) => s.sessionId).toList(), [newerId, olderId]);
  });

  test('translation_summary.json が欠損していてもセッション自体は一覧に残る(途中失敗時の復元)', () async {
    const sessionId = '2026-08-03T10-00-00';
    await SessionPaths(
      profileDirectory: tempDir,
      sessionId: sessionId,
    ).sessionDirectory.create(recursive: true);

    final sessions = await const HistoryRepository().listSessions(
      localizerLogsDirectory(tempDir),
    );

    expect(sessions.single.sessionId, sessionId);
    expect(sessions.single.summary, isNull);
  });

  test(
    'logs/localizer が存在しない任意のディレクトリを指定しても空リストを返す(アクティブなプロファイルに依存しない)',
    () async {
      final otherDirectory = await Directory.systemTemp.createTemp(
        'other_dir_',
      );
      addTearDown(() async {
        if (await otherDirectory.exists()) {
          await otherDirectory.delete(recursive: true);
        }
      });

      final sessions = await const HistoryRepository().listSessions(
        localizerLogsDirectory(otherDirectory),
      );

      expect(sessions, isEmpty);
    },
  );

  test('readSessionLog がセッションログファイルの内容を LogEntry として読み出す', () async {
    const sessionId = '2026-08-04T10-00-00';
    final logger = SessionLogger();
    await logger.beginSession(profileDirectory: tempDir, sessionId: sessionId);
    logger.log(LogLevel.info, 'translate', '開始', isMilestone: true);
    logger.log(LogLevel.error, 'translate', '失敗');
    await logger.endSession();

    final sessionDirectory = SessionPaths(
      profileDirectory: tempDir,
      sessionId: sessionId,
    ).sessionDirectory;

    final logEntries = await const HistoryRepository().readSessionLog(
      sessionDirectory,
    );

    expect(logEntries.length, 2);
    expect(logEntries[0].message, '開始');
    expect(logEntries[1].level, LogLevel.error);
  });

  test('ログファイルが無いセッションでは readSessionLog が空リストを返す', () async {
    final sessionDirectory = Directory(p.join(tempDir.path, 'no_log_here'));
    await sessionDirectory.create(recursive: true);

    final logEntries = await const HistoryRepository().readSessionLog(
      sessionDirectory,
    );

    expect(logEntries, isEmpty);
  });
}
