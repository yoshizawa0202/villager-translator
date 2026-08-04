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
/// 明示的な操作として残す(受け入れ条件5)。保存が完了したタイミングは
/// [_SaveStatusIndicator] で視覚的に示す(#9)。
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key, this.isTranslationRunning = false});

  /// いずれかのタブが翻訳中・スキャン中のときに `true`。
  ///
  /// この画面での変更は実行開始時点のスナップショットを使う現在実行中の
  /// 翻訳ジョブには反映されないため、その旨を注意書きとして表示する(#9)。
  final bool isTranslationRunning;

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
        children: [
          if (isTranslationRunning) ...[
            const _TranslationRunningNotice(),
            const SizedBox(height: 12),
          ],
          const _SaveStatusIndicator(),
          const SizedBox(height: 16),
          const _SectionHeader('LLM 設定'),
          const ProviderSelector(),
          const SizedBox(height: 12),
          const ApiKeyField(),
          const SizedBox(height: 12),
          const ModelSelector(),
          const SizedBox(height: 12),
          const LlmAdvancedSettingsSection(),
          const SizedBox(height: 24),
          const _SectionHeader('プロンプト'),
          const PromptEditorSection(),
          const SizedBox(height: 24),
          const _SectionHeader('翻訳設定'),
          const TranslationSettingsSection(),
          const SizedBox(height: 24),
          const _SectionHeader('対象言語'),
          const LanguageManagementButton(),
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

/// 翻訳実行中に設定画面を開いた場合の注意書き(#9)。
///
/// この画面での変更は現在実行中の翻訳ジョブ(実行開始時点のスナップショットを
/// 使用)には反映されず、次回の実行から適用されることを明示する。
class _TranslationRunningNotice extends StatelessWidget {
  const _TranslationRunningNotice();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      key: const Key('translationRunningNotice'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, color: colorScheme.onErrorContainer),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '翻訳を実行中です。ここでの変更は現在実行中の翻訳には反映されず、次回の実行から適用されます。',
              style: TextStyle(color: colorScheme.onErrorContainer),
            ),
          ),
        ],
      ),
    );
  }
}

/// 設定の保存状態を示すインジケーター(#9)。
///
/// 自動保存方式のため、いつ保存が完了したのかが視覚的に分かりづらいという
/// 課題を解消するために、直近の保存完了時刻を表示する。
class _SaveStatusIndicator extends StatelessWidget {
  const _SaveStatusIndicator();

  @override
  Widget build(BuildContext context) {
    final lastSavedAt = context.watch<SettingsController>().lastSavedAt;
    final textStyle = Theme.of(context).textTheme.bodySmall?.copyWith(
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    );

    if (lastSavedAt == null) {
      return Text(
        key: const Key('settingsSaveStatus'),
        '変更内容は入力するたびに自動的に保存されます',
        style: textStyle,
      );
    }

    return Row(
      key: const Key('settingsSaveStatus'),
      children: [
        Icon(
          Icons.check_circle,
          size: 14,
          color: Theme.of(context).colorScheme.primary,
        ),
        const SizedBox(width: 4),
        Text('保存しました(${_formatTime(lastSavedAt)})', style: textStyle),
      ],
    );
  }

  String _formatTime(DateTime time) {
    String pad(int value) => value.toString().padLeft(2, '0');
    return '${pad(time.hour)}:${pad(time.minute)}:${pad(time.second)}';
  }
}
