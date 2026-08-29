import 'package:flutter/material.dart';

import '../../../domain/instancetranslation/instance_translation_estimate.dart';

/// 翻訳前サマリー確認ダイアログ(012-instance-batch-translation.md §6)。
///
/// 大量の API リクエストが発生し得るため、実行前に必ず対象件数と文字列数を
/// 確認できるようにする。「戻る」を選ぶと実行しない(AC-06)。
class InstanceTranslationSummaryDialog extends StatelessWidget {
  const InstanceTranslationSummaryDialog({
    super.key,
    required this.instanceName,
    required this.estimate,
    required this.modelLabel,
    required this.languageLabel,
    required this.modeLabel,
  });

  final String instanceName;
  final InstanceTranslationEstimate estimate;
  final String modelLabel;
  final String languageLabel;
  final String modeLabel;

  /// ダイアログを表示し、「翻訳開始」が選択された場合のみ `true` を返す。
  static Future<bool> show(
    BuildContext context, {
    required String instanceName,
    required InstanceTranslationEstimate estimate,
    required String modelLabel,
    required String languageLabel,
    required String modeLabel,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => InstanceTranslationSummaryDialog(
        instanceName: instanceName,
        estimate: estimate,
        modelLabel: modelLabel,
        languageLabel: languageLabel,
        modeLabel: modeLabel,
      ),
    );
    return confirmed ?? false;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      key: const Key('instanceTranslationSummaryDialog'),
      title: const Text('翻訳対象を確認してください'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                instanceName,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              for (final category in estimate.categories)
                ListTile(
                  key: Key('summaryCategory_${category.label}'),
                  dense: true,
                  title: Text(category.label),
                  subtitle: Text(
                    '${category.itemCount} 件 / ${category.stringCount} 文字列',
                  ),
                ),
              const Divider(),
              ListTile(
                dense: true,
                title: const Text('合計'),
                subtitle: Text(
                  '${estimate.totalStringCount} 文字列',
                  key: const Key('summaryTotalStringCount'),
                ),
              ),
              if (estimate.isUpperBound)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    '差分更新のため、実際に翻訳される文字列数はこれより少なくなります'
                    '(既存キーの確認は翻訳直前に行われます)。',
                    key: Key('summaryUpperBoundNote'),
                  ),
                ),
              const Divider(),
              ListTile(
                dense: true,
                title: const Text('モデル'),
                subtitle: Text(modelLabel, key: const Key('summaryModelLabel')),
              ),
              ListTile(
                dense: true,
                title: const Text('対象言語'),
                subtitle: Text(
                  languageLabel,
                  key: const Key('summaryLanguageLabel'),
                ),
              ),
              ListTile(
                dense: true,
                title: const Text('翻訳モード'),
                subtitle: Text(modeLabel, key: const Key('summaryModeLabel')),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          key: const Key('instanceTranslationSummaryBackButton'),
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('戻る'),
        ),
        FilledButton(
          key: const Key('instanceTranslationSummaryStartButton'),
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('翻訳開始'),
        ),
      ],
    );
  }
}
