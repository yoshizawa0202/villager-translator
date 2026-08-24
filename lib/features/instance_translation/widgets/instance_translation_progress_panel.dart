import 'package:flutter/material.dart';

import '../../../domain/common/translation_progress.dart';
import '../../../domain/instancetranslation/instance_translation_outcome.dart';
import '../../shell/widgets/translation_progress_panel.dart';

/// カテゴリ別と全体の進捗を積んで表示するラッパー
/// (012-instance-batch-translation.md §9)。
///
/// 進捗モデルは既存の [OverallProgress] / [ChunkProgress] をそのまま使い、
/// 全体進捗の行には既存の [TranslationProgressPanel] を再利用する。ここが
/// 新設するのはカテゴリ行を積む部分だけ。
class InstanceTranslationProgressPanel extends StatelessWidget {
  const InstanceTranslationProgressPanel({
    super.key,
    required this.instanceName,
    required this.categoryProgress,
    required this.overallProgress,
    required this.singleFileProgress,
    required this.currentItemName,
    this.onCancel,
    this.isCancelling = false,
  });

  final String instanceName;

  /// カテゴリ別の進捗(未着手のカテゴリは値を持たない)。
  final Map<InstanceTranslationCategory, OverallProgress?> categoryProgress;

  final OverallProgress overallProgress;
  final ChunkProgress? singleFileProgress;
  final String? currentItemName;

  final VoidCallback? onCancel;
  final bool isCancelling;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const Key('instanceTranslationProgressPanel'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '$instanceName を翻訳しています',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 12),
        for (final category in InstanceTranslationCategory.values)
          _CategoryProgressRow(
            category: category,
            progress: categoryProgress[category],
          ),
        const Divider(height: 24),
        TranslationProgressPanel(
          overallProgress: overallProgress,
          singleFileProgress: singleFileProgress,
          currentItemName: currentItemName,
          onCancel: onCancel,
          isCancelling: isCancelling,
        ),
      ],
    );
  }
}

class _CategoryProgressRow extends StatelessWidget {
  const _CategoryProgressRow({required this.category, required this.progress});

  final InstanceTranslationCategory category;
  final OverallProgress? progress;

  @override
  Widget build(BuildContext context) {
    final current = progress;

    return Padding(
      key: Key('categoryProgress_${category.name}'),
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(category.displayName),
          const SizedBox(height: 4),
          LinearProgressIndicator(value: current?.fraction ?? 0),
          const SizedBox(height: 4),
          Text(
            current == null
                ? '未実行'
                : '${current.completedItems} / ${current.totalItems} '
                      '(${current.percent}%)',
            key: Key('categoryProgressLabel_${category.name}'),
          ),
        ],
      ),
    );
  }
}
