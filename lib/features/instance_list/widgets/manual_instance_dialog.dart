import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

/// インスタンスを手動追加するダイアログ
/// (011-launcher-instance-discovery.md §15.1)。
///
/// 自動検出できないカスタム Launcher・Portable 環境・独自 Minecraft 環境・
/// サーバーパック等のために、フォルダのパスを直接登録できるようにする。
/// パスの妥当性判定([InstanceListController.addManualPath])は呼び出し側が行う。
class ManualInstanceDialog extends StatefulWidget {
  const ManualInstanceDialog({super.key});

  /// ダイアログを表示し、登録するパスを返す(キャンセル時は `null`)。
  static Future<String?> show(BuildContext context) {
    return showDialog<String>(
      context: context,
      builder: (_) => const ManualInstanceDialog(),
    );
  }

  @override
  State<ManualInstanceDialog> createState() => _ManualInstanceDialogState();
}

class _ManualInstanceDialogState extends State<ManualInstanceDialog> {
  final _pathController = TextEditingController();

  @override
  void dispose() {
    _pathController.dispose();
    super.dispose();
  }

  void _submit() => Navigator.of(context).pop(_pathController.text);

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      key: const Key('manualInstanceDialog'),
      title: const Text('インスタンスを手動追加'),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Minecraft インスタンスのフォルダ、または '
              'ランチャーのフォルダ(instances / profiles を含むフォルダ)を指定します。',
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    key: const Key('manualInstancePathField'),
                    controller: _pathController,
                    decoration: const InputDecoration(labelText: 'フォルダのパス'),
                    onSubmitted: (_) => _submit(),
                  ),
                ),
                const SizedBox(width: 12),
                OutlinedButton(
                  key: const Key('manualInstanceBrowseButton'),
                  onPressed: () async {
                    final path = await getDirectoryPath();
                    if (path != null) _pathController.text = path;
                  },
                  child: const Text('参照'),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          key: const Key('manualInstanceCancelButton'),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('キャンセル'),
        ),
        FilledButton(
          key: const Key('manualInstanceConfirmButton'),
          onPressed: _submit,
          child: const Text('追加'),
        ),
      ],
    );
  }
}
