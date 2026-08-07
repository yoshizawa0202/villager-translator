import 'package:flutter/material.dart';

/// 翻訳キャンセルの確認ダイアログ(feature-spec.md §10、Issue #7)。
///
/// 誤操作による実行中翻訳の喪失を防ぐため、キャンセル操作の前に確認する。
/// 4機能共通の単一ダイアログとして使う(機能固有の知識を持たない)。
class CancelConfirmationDialog extends StatelessWidget {
  const CancelConfirmationDialog({super.key});

  /// ダイアログを表示し、「キャンセルする」が選択された場合のみ `true` を返す。
  static Future<bool> show(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => const CancelConfirmationDialog(),
    );
    return confirmed ?? false;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      key: const Key('cancelConfirmationDialog'),
      title: const Text('翻訳をキャンセルしますか?'),
      content: const Text(
        '現在処理中のチャンクが完了した時点で翻訳を停止します。'
        'それまでに完了した内容は保存され、未完了の内容は翻訳されません。',
      ),
      actions: [
        TextButton(
          key: const Key('cancelConfirmationDialogDismiss'),
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('戻る'),
        ),
        FilledButton(
          key: const Key('cancelConfirmationDialogConfirm'),
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('キャンセルする'),
        ),
      ],
    );
  }
}
