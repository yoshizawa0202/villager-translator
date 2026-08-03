import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../settings_controller.dart';

/// 対象言語管理ダイアログ(feature-spec.md §3.3、受け入れ条件8)。
///
/// 既定9言語は削除できない。カスタム言語は追加・削除できる。
class LanguageManagementDialog extends StatefulWidget {
  const LanguageManagementDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showDialog<void>(
      context: context,
      builder: (context) => const LanguageManagementDialog(),
    );
  }

  @override
  State<LanguageManagementDialog> createState() =>
      _LanguageManagementDialogState();
}

class _LanguageManagementDialogState extends State<LanguageManagementDialog> {
  final _idController = TextEditingController();
  final _nameController = TextEditingController();
  String? _errorMessage;

  @override
  void dispose() {
    _idController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<SettingsController>();
    final languages = controller.settings.translation.allLanguages;

    return AlertDialog(
      title: const Text('対象言語の管理'),
      content: SizedBox(
        width: 420,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 360),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Flexible(
                child: ListView(
                  key: const Key('languageList'),
                  shrinkWrap: true,
                  children: languages
                      .map(
                        (lang) => ListTile(
                          key: Key('language_${lang.id}'),
                          title: Text(lang.displayName),
                          subtitle: Text(lang.id),
                          trailing: lang.isDefault
                              ? const Tooltip(
                                  message: '既定言語は削除できません',
                                  child: Icon(Icons.lock),
                                )
                              : IconButton(
                                  key: Key('removeLanguage_${lang.id}'),
                                  icon: const Icon(Icons.delete),
                                  onPressed: () => context
                                      .read<SettingsController>()
                                      .removeCustomLanguage(lang.id),
                                ),
                        ),
                      )
                      .toList(),
                ),
              ),
              const Divider(),
              TextField(
                key: const Key('newLanguageIdField'),
                controller: _idController,
                decoration: const InputDecoration(labelText: '言語 ID(例: xx_xx)'),
              ),
              TextField(
                key: const Key('newLanguageNameField'),
                controller: _nameController,
                decoration: const InputDecoration(labelText: '表示名'),
              ),
              if (_errorMessage != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    _errorMessage!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  key: const Key('addLanguageButton'),
                  onPressed: _addLanguage,
                  child: const Text('追加'),
                ),
              ),
            ],
          ),
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

  Future<void> _addLanguage() async {
    final controller = context.read<SettingsController>();
    final error = await controller.addCustomLanguage(
      _idController.text,
      _nameController.text,
    );
    if (!mounted) return;
    setState(() => _errorMessage = error);
    if (error == null) {
      _idController.clear();
      _nameController.clear();
    }
  }
}

/// 対象言語管理ダイアログを開くためのボタン。
class LanguageManagementButton extends StatelessWidget {
  const LanguageManagementButton({super.key});

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      key: const Key('openLanguageManagementButton'),
      onPressed: () => LanguageManagementDialog.show(context),
      icon: const Icon(Icons.language),
      label: const Text('対象言語の管理'),
    );
  }
}
