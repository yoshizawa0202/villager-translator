import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../domain/common/translation_summary.dart';
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
///
/// ログの保存先は2系統(Issue#10)。
/// - **プロファイルログ**([profileDirectory] 配下): [isMilestone] が
///   `true` のエントリ(開始・対象ファイルごとの成功/失敗・完了サマリ・
///   トップレベルの例外)のみを書き出す粗い粒度のログ。
/// - **アプリケーションログ**([applicationSupportDirectory] 配下、
///   プロファイルに依存しない): [isMilestone] の値に関わらず全エントリ
///   (チャンク単位の詳細な実行内容・結果を含む)を書き出す。
///   [applicationSupportDirectory] が `null` の場合は書き出さない。
class SessionLogger extends ChangeNotifier {
  SessionLogger({int capacity = 500, this.applicationSupportDirectory})
    : _capacity = capacity;

  final int _capacity;
  final Queue<LogEntry> _entries = Queue<LogEntry>();

  /// アプリケーションログの書き出し先(`{ここ}/logs/localizer/{sessionId}/`)。
  final Directory? applicationSupportDirectory;

  IOSink? _profileSink;
  IOSink? _applicationSink;

  /// 直近 [_capacity] 件のログ(古い順)。
  List<LogEntry> get entries => List.unmodifiable(_entries);

  /// 新しいセッションを開始し、以降のログをセッションディレクトリへ追記する。
  /// 既存のセッションが開いていれば、まず終了させる。
  Future<void> beginSession({
    required Directory profileDirectory,
    required String sessionId,
  }) async {
    await endSession();
    final profilePaths = SessionPaths(
      profileDirectory: profileDirectory,
      sessionId: sessionId,
    );
    await profilePaths.sessionDirectory.create(recursive: true);
    _profileSink = profilePaths.logFile.openWrite(mode: FileMode.append);

    final applicationDirectory = applicationSupportDirectory;
    if (applicationDirectory != null) {
      final applicationPaths = SessionPaths(
        profileDirectory: applicationDirectory,
        sessionId: sessionId,
      );
      await applicationPaths.sessionDirectory.create(recursive: true);
      _applicationSink = applicationPaths.logFile.openWrite(
        mode: FileMode.append,
      );
    }
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
    _applicationSink?.writeln(entry.toLogLine());
    if (isMilestone) {
      _profileSink?.writeln(entry.toLogLine());
    }
    notifyListeners();
  }

  /// 現在のセッションのログファイルを閉じる(セッションが開いていなければ何もしない)。
  Future<void> endSession() async {
    final profileSink = _profileSink;
    _profileSink = null;
    if (profileSink != null) {
      await profileSink.flush();
      await profileSink.close();
    }

    final applicationSink = _applicationSink;
    _applicationSink = null;
    if (applicationSink != null) {
      await applicationSink.flush();
      await applicationSink.close();
    }
  }

  @override
  void dispose() {
    unawaited(endSession());
    super.dispose();
  }
}

/// [TranslationSummary] を対象ファイル単位の粗いログとして書き出す
/// (Issue#10: 「何の MOD ファイルに対し、翻訳が成功・失敗したか」)。
/// [isMilestone] 付きで記録するため、プロファイルログにも残る。
extension SessionLoggerSummaryLogging on SessionLogger {
  void logSummaryItems(TranslationSummary summary) {
    for (final item in summary.items) {
      final label = item.displayName ?? item.id;
      log(
        item.success ? LogLevel.info : LogLevel.warning,
        'translate.item',
        '[${item.type.name}] $label: '
            '${item.success ? '成功' : '失敗'} '
            '(${item.translatedKeyCount}/${item.totalKeyCount} キー)',
        isMilestone: true,
      );
    }
  }
}
