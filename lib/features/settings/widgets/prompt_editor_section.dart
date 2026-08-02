import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../settings_controller.dart';

/// システムプロンプト・ユーザープロンプトの編集(feature-spec.md §4.3、受け入れ条件9)。
///
/// プレースホルダーの説明として `{language}` `{line_count}` `{content}` の
/// 単一波括弧の3種のみを表示する(`{{x}}` 系は表示・サポートしない)。
class PromptEditorSection extends StatefulWidget {
  const PromptEditorSection({super.key});

  @override
  State<PromptEditorSection> createState() => _PromptEditorSectionState();
}

class _PromptEditorSectionState extends State<PromptEditorSection> {
  late final TextEditingController _systemController;
  late final TextEditingController _userController;

  @override
  void initState() {
    super.initState();
    final llm = context.read<SettingsController>().settings.llm;
    _systemController = TextEditingController(text: llm.systemPrompt);
    _userController = TextEditingController(text: llm.userPrompt);
  }

  @override
  void dispose() {
    _systemController.dispose();
    _userController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '利用できるプレースホルダー: {language}(対象言語) / {line_count}(行数) / {content}(本文)',
        ),
        const SizedBox(height: 8),
        TextFormField(
          key: const Key('systemPromptField'),
          controller: _systemController,
          decoration: const InputDecoration(labelText: 'システムプロンプト'),
          maxLines: 6,
          onFieldSubmitted: (value) => _saveSystemPrompt(context, value),
          onEditingComplete: () =>
              _saveSystemPrompt(context, _systemController.text),
        ),
        const SizedBox(height: 16),
        TextFormField(
          key: const Key('userPromptField'),
          controller: _userController,
          decoration: const InputDecoration(labelText: 'ユーザープロンプト'),
          maxLines: 6,
          onFieldSubmitted: (value) => _saveUserPrompt(context, value),
          onEditingComplete: () =>
              _saveUserPrompt(context, _userController.text),
        ),
      ],
    );
  }

  void _saveSystemPrompt(BuildContext context, String value) {
    context.read<SettingsController>().updateLlm(
      (s) => s.copyWith(systemPrompt: value),
    );
  }

  void _saveUserPrompt(BuildContext context, String value) {
    context.read<SettingsController>().updateLlm(
      (s) => s.copyWith(userPrompt: value),
    );
  }
}
