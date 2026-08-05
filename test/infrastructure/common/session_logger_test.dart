import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:villager_translator/infrastructure/common/session_logger.dart';
import 'package:villager_translator/infrastructure/common/session_paths.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('session_logger_test_');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('リングバッファは容量を超えると古いエントリから破棄する', () {
    final logger = SessionLogger(capacity: 2);
    logger.log(LogLevel.info, 'scan', '1件目');
    logger.log(LogLevel.info, 'scan', '2件目');
    logger.log(LogLevel.info, 'scan', '3件目');

    expect(logger.entries.length, 2);
    expect(logger.entries.map((e) => e.message), ['2件目', '3件目']);
  });

  test('notifyListeners がログ追加のたびに発火する', () {
    final logger = SessionLogger();
    var notifyCount = 0;
    logger.addListener(() => notifyCount++);

    logger.log(LogLevel.info, 'scan', 'メッセージ');

    expect(notifyCount, 1);
  });

  test('beginSession 後、isMilestone なログのみがプロファイルのログファイルへ永続化される', () async {
    final logger = SessionLogger();
    const sessionId = '2026-08-04T12-00-00';

    await logger.beginSession(profileDirectory: tempDir, sessionId: sessionId);
    logger.log(LogLevel.info, 'translate', '翻訳開始', isMilestone: true);
    logger.log(LogLevel.debug, 'translate.chunk', 'チャンク詳細');
    await logger.endSession();

    final logFile = File(
      p.joinAll([tempDir.path, 'logs', 'localizer', sessionId, 'session.log']),
    );
    expect(await logFile.exists(), isTrue);

    final lines = await logFile.readAsLines();
    expect(lines.length, 1);

    final entry = LogEntry.tryParseLogLine(lines[0]);
    expect(entry, isNotNull);
    expect(entry!.level, LogLevel.info);
    expect(entry.category, 'translate');
    expect(entry.message, '翻訳開始');
    expect(entry.isMilestone, isTrue);
  });

  test('applicationSupportDirectory を指定すると isMilestone に関わらず全ログをアプリケーションログへ永続化する', () async {
    final appDir = await Directory.systemTemp.createTemp(
      'session_logger_app_test_',
    );
    addTearDown(() async {
      if (await appDir.exists()) {
        await appDir.delete(recursive: true);
      }
    });

    final logger = SessionLogger(applicationSupportDirectory: appDir);
    const sessionId = '2026-08-04T12-00-00';

    await logger.beginSession(profileDirectory: tempDir, sessionId: sessionId);
    logger.log(LogLevel.info, 'translate', '翻訳開始', isMilestone: true);
    logger.log(LogLevel.debug, 'translate.chunk', 'チャンク詳細');
    await logger.endSession();

    final appLogFile = File(
      p.joinAll([appDir.path, 'logs', 'localizer', sessionId, 'session.log']),
    );
    final appLines = await appLogFile.readAsLines();
    expect(appLines.length, 2);

    final profileLogFile = File(
      p.joinAll([tempDir.path, 'logs', 'localizer', sessionId, 'session.log']),
    );
    final profileLines = await profileLogFile.readAsLines();
    expect(profileLines.length, 1);
  });

  test('beginSession 前のログはメモリ上のみでファイルへ永続化されない', () async {
    final logger = SessionLogger();
    logger.log(LogLevel.info, 'scan', 'スキャン中のログ');

    expect(logger.entries.length, 1);
    final logsRoot = Directory(p.join(tempDir.path, 'logs'));
    expect(await logsRoot.exists(), isFalse);
  });

  test('SessionPaths と組み合わせて同一セッションディレクトリ配下に書き込む', () async {
    final logger = SessionLogger();
    const sessionId = '2026-08-04T12-00-00';
    await logger.beginSession(profileDirectory: tempDir, sessionId: sessionId);
    logger.log(LogLevel.info, 'translate', 'ok');
    await logger.endSession();

    final paths = SessionPaths(profileDirectory: tempDir, sessionId: sessionId);
    expect(await paths.logFile.exists(), isTrue);
  });
}
