import 'package:flutter/material.dart';

import '../../../domain/common/translation_summary.dart';

/// 翻訳完了サマリダイアログ(feature-spec.md §3.2、
/// 008-progress-log-history.md 受け入れ条件8)。
///
/// 成功/失敗/合計件数、検索可能な結果一覧、「ログ表示」ボタンを提供する。
/// 4機能共通の単一ダイアログとして使う([TranslationSummary]を消費するのみで、
/// 機能固有の知識を持たない)。
class TranslationCompletionDialog extends StatefulWidget {
  const TranslationCompletionDialog({
    super.key,
    required this.summary,
    required this.onShowLog,
  });

  final TranslationSummary summary;
  final VoidCallback onShowLog;

  static Future<void> show(
    BuildContext context, {
    required TranslationSummary summary,
    required VoidCallback onShowLog,
  }) {
    return showDialog<void>(
      context: context,
      builder: (_) =>
          TranslationCompletionDialog(summary: summary, onShowLog: onShowLog),
    );
  }

  @override
  State<TranslationCompletionDialog> createState() =>
      _TranslationCompletionDialogState();
}

class _TranslationCompletionDialogState
    extends State<TranslationCompletionDialog> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final query = _query.trim().toLowerCase();
    final items = widget.summary.items.where((item) {
      if (query.isEmpty) return true;
      return item.id.toLowerCase().contains(query) ||
          (item.displayName?.toLowerCase().contains(query) ?? false);
    }).toList();

    return AlertDialog(
      title: const Text('翻訳が完了しました'),
      content: SizedBox(
        width: 480,
        height: 420,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '成功 ${widget.summary.successCount} / '
              '失敗 ${widget.summary.failureCount} / '
              '合計 ${widget.summary.totalCount} 件',
              key: const Key('completionDialogCounts'),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('completionDialogSearchField'),
              decoration: const InputDecoration(labelText: '検索'),
              onChanged: (value) => setState(() => _query = value),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: ListView.builder(
                key: const Key('completionDialogResultList'),
                itemCount: items.length,
                itemBuilder: (context, index) {
                  final item = items[index];
                  return ListTile(
                    dense: true,
                    leading: Icon(
                      item.success ? Icons.check_circle : Icons.error,
                      color: item.success ? Colors.green : Colors.red,
                    ),
                    title: Text(item.displayName ?? item.id),
                    subtitle: Text(
                      '${item.translatedKeyCount} / ${item.totalKeyCount} キー',
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          key: const Key('completionDialogShowLogButton'),
          onPressed: widget.onShowLog,
          child: const Text('ログ表示'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('閉じる'),
        ),
      ],
    );
  }
}
