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

  test('beginSession 後のログはセッションログファイルへ日時・レベル・処理種別・メッセージ付きで永続化される', () async {
    final logger = SessionLogger();
    const sessionId = '2026-08-04T12-00-00';

    await logger.beginSession(profileDirectory: tempDir, sessionId: sessionId);
    logger.log(LogLevel.info, 'translate', '翻訳開始', isMilestone: true);
    logger.log(LogLevel.error, 'translate', '失敗しました');
    await logger.endSession();

    final logFile = File(
      p.joinAll([tempDir.path, 'logs', 'localizer', sessionId, 'session.log']),
    );
    expect(await logFile.exists(), isTrue);

    final lines = await logFile.readAsLines();
    expect(lines.length, 2);

    final firstEntry = LogEntry.tryParseLogLine(lines[0]);
    expect(firstEntry, isNotNull);
    expect(firstEntry!.level, LogLevel.info);
    expect(firstEntry.category, 'translate');
    expect(firstEntry.message, '翻訳開始');
    expect(firstEntry.isMilestone, isTrue);

    final secondEntry = LogEntry.tryParseLogLine(lines[1]);
    expect(secondEntry!.level, LogLevel.error);
    expect(secondEntry.isMilestone, isFalse);
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
