import 'package:flutter/material.dart';

import '../../../domain/common/translation_progress.dart';

/// 翻訳実行中の進捗を視覚的に表示するパネル(feature-spec.md §10、Issue #7)。
///
/// 単一ファイル進捗・全体進捗をそれぞれプログレスバーとテキストで表示し、
/// 現在処理中の対象(MOD 名やファイル相対パスなど)をあわせて表示する。
/// [onCancel] を渡すと、プログレスバー付近にキャンセルボタンを表示する
/// (Issue #7)。ボタン押下時の確認ダイアログ表示は呼び出し側の責務とする
/// ([CancelConfirmationDialog])。
/// 4機能共通の単一ウィジェットとして使う([OverallProgress]/[ChunkProgress]を
/// 消費するのみで、機能固有の知識を持たない)。
class TranslationProgressPanel extends StatelessWidget {
  const TranslationProgressPanel({
    super.key,
    required this.overallProgress,
    required this.singleFileProgress,
    required this.currentItemName,
    this.onCancel,
    this.isCancelling = false,
  });

  final OverallProgress? overallProgress;
  final ChunkProgress? singleFileProgress;
  final String? currentItemName;

  /// キャンセルボタン押下時のコールバック。`null` の場合はボタンを表示しない。
  final VoidCallback? onCancel;

  /// キャンセル要求済み(協調的キャンセルの完了待ち中)かどうか。
  /// `true` の間はボタンを無効化し、二重押下を防ぐ。
  final bool isCancelling;

  @override
  Widget build(BuildContext context) {
    final overall = overallProgress;
    if (overall == null) return const SizedBox.shrink();

    final single = singleFileProgress;

    return Row(
      key: const Key('translationProgressPanel'),
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
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
                child: Text(
                  overall.label,
                  key: const Key('overallProgressLabel'),
                ),
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
          ),
        ),
        if (onCancel != null) ...[
          const SizedBox(width: 12),
          OutlinedButton.icon(
            key: const Key('cancelTranslationButton'),
            onPressed: isCancelling ? null : onCancel,
            icon: const Icon(Icons.cancel_outlined),
            label: Text(isCancelling ? 'キャンセル中...' : 'キャンセル'),
          ),
        ],
      ],
    );
  }
}
