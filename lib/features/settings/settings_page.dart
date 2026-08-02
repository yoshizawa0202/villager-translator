import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'settings_controller.dart';
import 'widgets/api_key_field.dart';
import 'widgets/language_management_dialog.dart';
import 'widgets/llm_advanced_settings_section.dart';
import 'widgets/model_selector.dart';
import 'widgets/prompt_editor_section.dart';
import 'widgets/provider_selector.dart';
import 'widgets/translation_settings_section.dart';

/// 設定画面(feature-spec.md §4)。
///
/// 各項目の変更は即座に検証・保存される(自動保存方式)。「デフォルトに戻す」のみ
/// 明示的な操作として残す(受け入れ条件5)。
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('設定'),
        actions: [
          TextButton(
            key: const Key('resetToDefaultsButton'),
            onPressed: () => _confirmReset(context),
            child: const Text(
              'デフォルトに戻す',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: const [
          _SectionHeader('LLM 設定'),
          ProviderSelector(),
          SizedBox(height: 12),
          ApiKeyField(),
          SizedBox(height: 12),
          ModelSelector(),
          SizedBox(height: 12),
          LlmAdvancedSettingsSection(),
          SizedBox(height: 24),
          _SectionHeader('プロンプト'),
          PromptEditorSection(),
          SizedBox(height: 24),
          _SectionHeader('翻訳設定'),
          TranslationSettingsSection(),
          SizedBox(height: 24),
          _SectionHeader('対象言語'),
          LanguageManagementButton(),
        ],
      ),
    );
  }

  Future<void> _confirmReset(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('デフォルトに戻す'),
        content: const Text('LLM 設定・翻訳設定・プロンプトを初期値に戻します。API キーは保持されます。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('キャンセル'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('戻す'),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      await context.read<SettingsController>().resetToDefaults();
    }
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(title, style: Theme.of(context).textTheme.titleLarge),
    );
  }
}
