import 'package:flutter/material.dart';

import '../../../domain/common/translation_progress.dart';

/// 翻訳実行中の進捗を視覚的に表示するパネル(feature-spec.md §10、Issue #7)。
///
/// 単一ファイル進捗・全体進捗をそれぞれプログレスバーとテキストで表示し、
/// 現在処理中の対象(MOD 名やファイル相対パスなど)をあわせて表示する。
/// 4機能共通の単一ウィジェットとして使う([OverallProgress]/[ChunkProgress]を
/// 消費するのみで、機能固有の知識を持たない)。
class TranslationProgressPanel extends StatelessWidget {
  const TranslationProgressPanel({
    super.key,
    required this.overallProgress,
    required this.singleFileProgress,
    required this.currentItemName,
  });

  final OverallProgress? overallProgress;
  final ChunkProgress? singleFileProgress;
  final String? currentItemName;

  @override
  Widget build(BuildContext context) {
    final overall = overallProgress;
    if (overall == null) return const SizedBox.shrink();

    final single = singleFileProgress;

    return Column(
      key: const Key('translationProgressPanel'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (currentItemName != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              '翻訳中: $currentItemName',
              key: const Key('currentItemLabel'),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        LinearProgressIndicator(
          key: const Key('overallProgressBar'),
          value: overall.fraction,
        ),
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(overall.label, key: const Key('overallProgressLabel')),
        ),
        if (single != null) ...[
          const SizedBox(height: 8),
          LinearProgressIndicator(
            key: const Key('singleFileProgressBar'),
            value: single.fraction,
          ),
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              '現在のファイル: ${single.completedChunks} / '
              '${single.totalChunks} チャンク完了 (${single.percent}%)',
              key: const Key('singleFileProgressLabel'),
            ),
          ),
        ],
      ],
    );
  }
}
