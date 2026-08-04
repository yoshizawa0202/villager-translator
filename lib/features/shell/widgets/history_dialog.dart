import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../../infrastructure/common/history_repository.dart';
import '../../../infrastructure/common/session_logger.dart';
import '../../../infrastructure/common/session_paths.dart';

/// 翻訳履歴ダイアログ(feature-spec.md §13、
/// 008-progress-log-history.md 受け入れ条件13・14)。
///
/// 現在アクティブなプロファイルディレクトリとは独立して、任意のディレクトリを
/// 指定して過去セッション一覧を閲覧できる。
class HistoryDialog extends StatefulWidget {
  const HistoryDialog({
    super.key,
    this.initialDirectory,
    this.repository = const HistoryRepository(),
  });

  final Directory? initialDirectory;
  final HistoryRepository repository;

  static Future<void> show(
    BuildContext context, {
    Directory? initialDirectory,
  }) {
    return showDialog<void>(
      context: context,
      builder: (_) => HistoryDialog(initialDirectory: initialDirectory),
    );
  }

  @override
  State<HistoryDialog> createState() => _HistoryDialogState();
}

class _HistoryDialogState extends State<HistoryDialog> {
  late final TextEditingController _directoryController;
  List<SessionHistoryEntry>? _sessions;
  final Map<Directory, Future<List<LogEntry>>> _logFutures = {};

  @override
  void initState() {
    super.initState();
    _directoryController = TextEditingController(
      text: widget.initialDirectory?.path ?? '',
    );
    if (widget.initialDirectory != null) {
      _load(widget.initialDirectory!);
    }
  }

  @override
  void dispose() {
    _directoryController.dispose();
    super.dispose();
  }

  Future<void> _load(Directory directory) async {
    final sessions = await widget.repository.listSessions(
      localizerLogsDirectory(directory),
    );
    if (!mounted) return;
    setState(() {
      _sessions = sessions;
      _logFutures.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('翻訳履歴'),
      content: SizedBox(
        width: 560,
        height: 480,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    key: const Key('historyDirectoryField'),
                    controller: _directoryController,
                    decoration: const InputDecoration(
                      labelText: 'プロファイルディレクトリ',
                    ),
                    onSubmitted: (path) => _load(Directory(path)),
                  ),
                ),
                const SizedBox(width: 12),
                OutlinedButton(
                  key: const Key('historyBrowseDirectoryButton'),
                  onPressed: () async {
                    final path = await getDirectoryPath();
                    if (path != null) {
                      _directoryController.text = path;
                      await _load(Directory(path));
                    }
                  },
                  child: const Text('参照'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(child: _buildSessionList()),
          ],
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

  Widget _buildSessionList() {
    final sessions = _sessions;
    if (sessions == null) {
      return const Center(child: Text('ディレクトリを指定してください'));
    }
    if (sessions.isEmpty) {
      return const Center(child: Text('セッションがありません'));
    }

    return ListView.builder(
      key: const Key('historySessionList'),
      itemCount: sessions.length,
      itemBuilder: (context, index) {
        final session = sessions[index];
        final summary = session.summary;
        return ExpansionTile(
          key: ValueKey('historySession_${session.sessionId}'),
          title: Text(session.sessionId),
          subtitle: summary != null
              ? Text(
                  '成功 ${summary.successCount} / 失敗 ${summary.failureCount} / '
                  '合計 ${summary.totalCount} 件',
                )
              : const Text('サマリなし(途中終了の可能性)'),
          children: [
            FutureBuilder<List<LogEntry>>(
              future: _logFutures.putIfAbsent(
                session.sessionDirectory,
                () =>
                    widget.repository.readSessionLog(session.sessionDirectory),
              ),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                final logs = snapshot.data!;
                if (logs.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('ログがありません'),
                  );
                }
                return Column(
                  children: logs
                      .map(
                        (e) => ListTile(
                          dense: true,
                          title: Text(e.message),
                          subtitle: Text(e.timestamp.toIso8601String()),
                        ),
                      )
                      .toList(),
                );
              },
            ),
          ],
        );
      },
    );
  }
}
