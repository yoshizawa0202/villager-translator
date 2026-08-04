import 'dart:convert';
import 'dart:io';

import '../../domain/common/translation_summary.dart';
import 'session_paths.dart';

/// 1回の翻訳実行の結果を `translation_summary.json` として永続化する
/// (feature-spec.md §13)。
class TranslationSummaryWriter {
  const TranslationSummaryWriter();

  Future<File> write({
    required Directory profileDirectory,
    required TranslationSummary summary,
  }) async {
    final paths = SessionPaths(
      profileDirectory: profileDirectory,
      sessionId: summary.sessionId,
    );
    await paths.sessionDirectory.create(recursive: true);
    final file = paths.summaryFile;
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(summary.toJson()),
    );
    return file;
  }
}
