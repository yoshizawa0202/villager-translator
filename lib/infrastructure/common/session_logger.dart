import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'session_paths.dart';

/// ログの重大度(feature-spec.md §11)。
enum LogLevel {
  debug,
  info,
  warning,
  error;

  static LogLevel? fromName(String name) {
    for (final value in LogLevel.values) {
      if (value.name == name) return value;
    }
    return null;
  }
}

/// ログ1件分のエントリ(日時・レベル・処理種別・メッセージ、feature-spec.md §11)。
class LogEntry {
  const LogEntry({
    required this.timestamp,
    required this.level,
    required this.category,
    required this.message,
    this.isMilestone = false,
  });

  final DateTime timestamp;
  final LogLevel level;

  /// 処理種別(例: `scan`、`translate`)。
  final String category;
  final String message;

  /// アイドル時の要約表示に残すべき節目かどうか(進捗の節目・エラー等)。
  final bool isMilestone;

  /// セッションログファイルへの1行分の表現(タブ区切り)。
  String toLogLine() {
    final flag = isMilestone ? '1' : '0';
    final escapedMessage = message.replaceAll('\n', r'\n');
    return '${timestamp.toIso8601String()}\t${level.name}\t$flag\t$category\t$escapedMessage';
  }

  /// [toLogLine] で書き出した1行から復元する。解釈できない行は `null`。
  static LogEntry? tryParseLogLine(String line) {
    final parts = line.split('\t');
    if (parts.length < 5) return null;

    final timestamp = DateTime.tryParse(parts[0]);
    final level = LogLevel.fromName(parts[1]);
    if (timestamp == null || level == null) return null;

    return LogEntry(
      timestamp: timestamp,
      level: level,
      isMilestone: parts[2] == '1',
      category: parts[3],
      message: parts.sublist(4).join('\t').replaceAll(r'\n', '\n'),
    );
  }
}

/// 処理ログのリングバッファ(直近N件、feature-spec.md §11)+リアルタイム通知+
/// セッションディレクトリへのファイル永続化を担う。
///
/// [beginSession] を呼ぶまではメモリ上のリングバッファのみを更新し、ディスクへ
/// は書き込まない(スキャン中などセッションディレクトリがまだ無い状態のログ用)。
class SessionLogger extends ChangeNotifier {
  SessionLogger({int capacity = 500}) : _capacity = capacity;

  final int _capacity;
  final Queue<LogEntry> _entries = Queue<LogEntry>();

  IOSink? _sink;

  /// 直近 [_capacity] 件のログ(古い順)。
  List<LogEntry> get entries => List.unmodifiable(_entries);

  /// 新しいセッションを開始し、以降のログをセッションディレクトリへ追記する。
  /// 既存のセッションが開いていれば、まず終了させる。
  Future<void> beginSession({
    required Directory profileDirectory,
    required String sessionId,
  }) async {
    await endSession();
    final paths = SessionPaths(
      profileDirectory: profileDirectory,
      sessionId: sessionId,
    );
    await paths.sessionDirectory.create(recursive: true);
    _sink = paths.logFile.openWrite(mode: FileMode.append);
  }

  void log(
    LogLevel level,
    String category,
    String message, {
    bool isMilestone = false,
  }) {
    final entry = LogEntry(
      timestamp: DateTime.now(),
      level: level,
      category: category,
      message: message,
      isMilestone: isMilestone,
    );

    _entries.addLast(entry);
    while (_entries.length > _capacity) {
      _entries.removeFirst();
    }
    _sink?.writeln(entry.toLogLine());
    notifyListeners();
  }

  /// 現在のセッションのログファイルを閉じる(セッションが開いていなければ何もしない)。
  Future<void> endSession() async {
    final sink = _sink;
    _sink = null;
    if (sink != null) {
      await sink.flush();
      await sink.close();
    }
  }

  @override
  void dispose() {
    unawaited(endSession());
    super.dispose();
  }
}
