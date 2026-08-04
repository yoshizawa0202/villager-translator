import 'package:flutter/material.dart';

import '../../../infrastructure/common/session_logger.dart';

/// ログビューアダイアログ(feature-spec.md §11、
/// 008-progress-log-history.md 受け入れ条件9・10)。
///
/// [isBusy] が真(翻訳中)なら詳細ログを、偽(アイドル)なら要約ログ
/// (エラー・節目のみ)を表示する。
class LogViewerDialog extends StatelessWidget {
  const LogViewerDialog({
    super.key,
    required this.logger,
    required this.isBusy,
  });

  final SessionLogger logger;
  final bool isBusy;

  static Future<void> show(
    BuildContext context, {
    required SessionLogger logger,
    required bool isBusy,
  }) {
    return showDialog<void>(
      context: context,
      builder: (_) => LogViewerDialog(logger: logger, isBusy: isBusy),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('ログ'),
      content: SizedBox(
        width: 480,
        height: 400,
        child: AnimatedBuilder(
          animation: logger,
          builder: (context, _) {
            final entries = logger.entries.reversed
                .where(
                  (e) => isBusy || e.level == LogLevel.error || e.isMilestone,
                )
                .toList();

            if (entries.isEmpty) {
              return const Center(child: Text('ログはありません'));
            }

            return ListView.builder(
              key: const Key('logViewerList'),
              itemCount: entries.length,
              itemBuilder: (context, index) {
                final entry = entries[index];
                return ListTile(
                  dense: true,
                  leading: Icon(_iconFor(entry.level)),
                  title: Text(entry.message),
                  subtitle: Text(
                    '${entry.timestamp.toIso8601String()} / ${entry.category}',
                  ),
                );
              },
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('閉じる'),
        ),
      ],
    );
  }

  IconData _iconFor(LogLevel level) {
    switch (level) {
      case LogLevel.debug:
        return Icons.bug_report_outlined;
      case LogLevel.info:
        return Icons.info_outline;
      case LogLevel.warning:
        return Icons.warning_amber_outlined;
      case LogLevel.error:
        return Icons.error_outline;
    }
  }
}
