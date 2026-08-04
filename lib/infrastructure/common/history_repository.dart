import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../domain/common/translation_summary.dart';
import 'session_logger.dart';

/// 過去の翻訳セッション1件分(feature-spec.md §13)。
class SessionHistoryEntry {
  const SessionHistoryEntry({
    required this.sessionId,
    required this.sessionDirectory,
    this.summary,
  });

  final String sessionId;
  final Directory sessionDirectory;

  /// `translation_summary.json` が存在しない・破損している場合は `null`
  /// (途中失敗したセッションでも一覧には残す、AGENTS.md「途中失敗時の復元」)。
  final TranslationSummary? summary;
}

/// 翻訳履歴(過去セッション一覧・詳細ログ)を読み出す
/// (feature-spec.md §13、受け入れ条件13・14)。
///
/// 現在アクティブなプロファイルディレクトリに依存せず、任意のディレクトリの
/// `logs/localizer/` を指定して読み出せる。
class HistoryRepository {
  const HistoryRepository();

  /// [logsLocalizerDirectory](`{任意のディレクトリ}/logs/localizer/`)配下の
  /// セッション一覧を、セッションID の降順(≒時系列降順)で返す。
  Future<List<SessionHistoryEntry>> listSessions(
    Directory logsLocalizerDirectory,
  ) async {
    if (!await logsLocalizerDirectory.exists()) return const [];

    final entries = <SessionHistoryEntry>[];
    await for (final entity in logsLocalizerDirectory.list()) {
      if (entity is! Directory) continue;

      final sessionId = p.basename(entity.path);
      final summary = await _tryReadSummary(entity);
      entries.add(
        SessionHistoryEntry(
          sessionId: sessionId,
          sessionDirectory: entity,
          summary: summary,
        ),
      );
    }

    entries.sort((a, b) => b.sessionId.compareTo(a.sessionId));
    return entries;
  }

  Future<TranslationSummary?> _tryReadSummary(
    Directory sessionDirectory,
  ) async {
    final file = File(
      p.join(sessionDirectory.path, 'translation_summary.json'),
    );
    if (!await file.exists()) return null;

    try {
      final content = await file.readAsString();
      final json = jsonDecode(content);
      if (json is! Map<String, dynamic>) return null;
      return TranslationSummary.fromJson(json);
    } catch (_) {
      return null;
    }
  }

  /// [sessionDirectory] のセッションログ(`session.log`)を読み出す。
  /// ファイルが存在しない場合は空リストを返す。
  Future<List<LogEntry>> readSessionLog(Directory sessionDirectory) async {
    final file = File(p.join(sessionDirectory.path, 'session.log'));
    if (!await file.exists()) return const [];

    final lines = await file.readAsLines();
    final entries = <LogEntry>[];
    for (final line in lines) {
      final entry = LogEntry.tryParseLogLine(line);
      if (entry != null) entries.add(entry);
    }
    return entries;
  }
}
