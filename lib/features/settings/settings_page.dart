import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'settings_controller.dart';
import 'widgets/api_key_field.dart';
import 'widgets/language_management_dialog.dart';
import 'widgets/llm_advanced_settings_section.dart';
import 'widgets/model_selector.dart';
import 'widgets/prompt_editor_section.dart';
import 'widgets/provider_selector.dart';
import 'widgets/thinking_level_selector.dart';
import 'widgets/translation_settings_section.dart';

/// 設定画面(feature-spec.md §4)。
///
/// 各項目の変更は検証のうえ画面内のドラフトにのみ反映され、右上の「保存」
/// ボタンを押したときにまとめて設定ファイル・セキュアストレージへ永続化される
/// (受け入れ条件13)。「デフォルトに戻す」は保存ボタンを介さず即時に反映される
/// (受け入れ条件5・17)。保存状態は [_SaveStatusIndicator] で視覚的に示し(#9)、
/// 未保存の変更がある状態で画面を閉じようとすると警告ダイアログを表示する
/// (受け入れ条件15)。
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key, this.isTranslationRunning = false});

  /// いずれかのタブが翻訳中・スキャン中のときに `true`。
  ///
  /// この画面での変更は実行開始時点のスナップショットを使う現在実行中の
  /// 翻訳ジョブには反映されないため、その旨を注意書きとして表示する(#9)。
  final bool isTranslationRunning;

  @override
  Widget build(BuildContext context) {
    final hasUnsavedChanges = context
        .watch<SettingsController>()
        .hasUnsavedChanges;

    return PopScope(
      canPop: !hasUnsavedChanges,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        await _confirmDiscardAndClose(context);
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('設定'),
          actionsPadding: const EdgeInsets.only(right: 16),
          actions: [
            TextButton(
              key: const Key('resetToDefaultsButton'),
              onPressed: () => _confirmReset(context),
              child: const Text(
                'デフォルトに戻す',
                style: TextStyle(color: Colors.white),
              ),
            ),
            TextButton(
              key: const Key('saveSettingsButton'),
              onPressed: () => _handleSave(context),
              child: const Text('保存', style: TextStyle(color: Colors.white)),
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
            const ThinkingLevelSelector(),
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
      ),
    );
  }

  /// フォーカスが残ったフィールドの入力中の値をドラフトへ確定してから保存する
  /// (フォーカスを失うと各フィールドの FocusNode リスナーがドラフトへ反映する)。
  /// フォーカス変更の通知は既定ではマイクロタスクまで遅延されるため、save() の
  /// 前に1マイクロタスク待って確実に確定させる。`FocusManager` の内部 API
  /// (`applyFocusChangesIfNeeded`)には依存しない。
  Future<void> _handleSave(BuildContext context) async {
    FocusScope.of(context).unfocus();
    await Future<void>.value();
    if (!context.mounted) return;
    await context.read<SettingsController>().save();
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

  Future<void> _confirmDiscardAndClose(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('保存されていない変更があります'),
        content: const Text('設定画面を閉じると、保存していない変更は破棄されます。破棄しますか?'),
        actions: [
          TextButton(
            key: const Key('discardChangesCancelButton'),
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('キャンセル'),
          ),
          TextButton(
            key: const Key('discardChangesConfirmButton'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('破棄して閉じる'),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      context.read<SettingsController>().discardChanges();
      Navigator.of(context).pop();
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

/// 設定の保存状態を示すインジケーター(#9、#11)。
///
/// 保存ボタン方式のため、未保存の変更があるかどうかと、直近の保存完了時刻を
/// 表示することで、保存タイミングを視覚的に分かりやすくする。
class _SaveStatusIndicator extends StatelessWidget {
  const _SaveStatusIndicator();

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<SettingsController>();
    final hasUnsavedChanges = controller.hasUnsavedChanges;
    final lastSavedAt = controller.lastSavedAt;
    final colorScheme = Theme.of(context).colorScheme;
    final textStyle = Theme.of(
      context,
    ).textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant);

    if (hasUnsavedChanges) {
      return Row(
        key: const Key('settingsSaveStatus'),
        children: [
          Icon(Icons.circle, size: 10, color: colorScheme.error),
          const SizedBox(width: 6),
          Text(
            '未保存の変更があります。「保存」ボタンを押すと反映されます',
            style: textStyle?.copyWith(color: colorScheme.error),
          ),
        ],
      );
    }

    if (lastSavedAt == null) {
      return Text(
        key: const Key('settingsSaveStatus'),
        '変更後に「保存」ボタンを押すと反映されます',
        style: textStyle,
      );
    }

    return Row(
      key: const Key('settingsSaveStatus'),
      children: [
        Icon(Icons.check_circle, size: 14, color: colorScheme.primary),
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
