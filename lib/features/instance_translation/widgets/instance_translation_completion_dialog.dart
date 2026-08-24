import 'package:flutter/material.dart';

import '../../../domain/instancetranslation/instance_translation_outcome.dart';

/// 一括翻訳の完了画面(012-instance-batch-translation.md §10、§12)。
///
/// カテゴリごとの成功・失敗・スキップ件数、出力先、バックアップ先、
/// セッションログを開く導線、失敗項目の再試行を提供する。
class InstanceTranslationCompletionDialog extends StatelessWidget {
  const InstanceTranslationCompletionDialog({
    super.key,
    required this.outcome,
    required this.onShowLog,
    required this.onRetryFailed,
  });

  final InstanceTranslationOutcome outcome;
  final VoidCallback onShowLog;

  /// 失敗した対象だけの再試行(§10)。失敗が無い場合はボタンを表示しない。
  final VoidCallback onRetryFailed;

  static Future<void> show(
    BuildContext context, {
    required InstanceTranslationOutcome outcome,
    required VoidCallback onShowLog,
    required VoidCallback onRetryFailed,
  }) {
    return showDialog<void>(
      context: context,
      builder: (_) => InstanceTranslationCompletionDialog(
        outcome: outcome,
        onShowLog: onShowLog,
        onRetryFailed: onRetryFailed,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      key: const Key('instanceTranslationCompletionDialog'),
      title: Text(outcome.cancelled ? '一括翻訳をキャンセルしました' : '翻訳完了'),
      content: SizedBox(
        width: 520,
        height: 420,
        child: ListView(
          children: [
            Text(
              '成功 ${outcome.successCount} 件 / '
              '失敗 ${outcome.failureCount} 件 / '
              'スキップ ${outcome.skippedCount} 件',
              key: const Key('instanceCompletionCounts'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const Divider(height: 24),
            for (final category in outcome.categories)
              _CategorySection(outcome: category),
          ],
        ),
      ),
      actions: [
        if (outcome.hasFailures)
          TextButton(
            key: const Key('retryFailedItemsButton'),
            onPressed: () {
              Navigator.of(context).pop();
              onRetryFailed();
            },
            child: const Text('失敗した項目を再試行'),
          ),
        TextButton(
          key: const Key('instanceCompletionShowLogButton'),
          onPressed: onShowLog,
          child: const Text('ログ表示'),
        ),
        TextButton(
          key: const Key('instanceCompletionCloseButton'),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('閉じる'),
        ),
      ],
    );
  }
}

class _CategorySection extends StatelessWidget {
  const _CategorySection({required this.outcome});

  final InstanceTranslationCategoryOutcome outcome;

  @override
  Widget build(BuildContext context) {
    if (!outcome.executed) {
      return ListTile(
        key: Key('completionCategory_${outcome.category.name}'),
        dense: true,
        title: Text(outcome.category.displayName),
        subtitle: const Text('未実行'),
      );
    }

    return Column(
      key: Key('completionCategory_${outcome.category.name}'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListTile(
          dense: true,
          title: Text(outcome.category.displayName),
          subtitle: Text(
            '成功 ${outcome.successIds.length} / '
            '失敗 ${outcome.failedIds.length} / '
            'スキップ ${outcome.skippedIds.length}',
            key: Key('completionCategoryCounts_${outcome.category.name}'),
          ),
        ),
        if (outcome.error != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'エラー: ${outcome.error}',
              key: Key('completionCategoryError_${outcome.category.name}'),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        for (final location in outcome.outputLocations)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text('出力先: $location'),
          ),
        if (outcome.backupLocation != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text('バックアップ: ${outcome.backupLocation}'),
          ),
        const SizedBox(height: 12),
      ],
    );
  }
}
