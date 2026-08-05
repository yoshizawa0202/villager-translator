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
  late final FocusNode _systemFocusNode;
  late final FocusNode _userFocusNode;

  @override
  void initState() {
    super.initState();
    final llm = context.read<SettingsController>().settings.llm;
    _systemController = TextEditingController(text: llm.systemPrompt);
    _userController = TextEditingController(text: llm.userPrompt);
    _systemFocusNode = FocusNode()
      ..addListener(() {
        if (!_systemFocusNode.hasFocus) {
          _saveSystemPrompt(context, _systemController.text);
        }
      });
    _userFocusNode = FocusNode()
      ..addListener(() {
        if (!_userFocusNode.hasFocus) {
          _saveUserPrompt(context, _userController.text);
        }
      });
  }

  @override
  void dispose() {
    _systemController.dispose();
    _userController.dispose();
    _systemFocusNode.dispose();
    _userFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<SettingsController>();
    final llm = controller.settings.llm;

    if (_systemController.text != llm.systemPrompt) {
      _systemController.text = llm.systemPrompt;
    }
    if (_userController.text != llm.userPrompt) {
      _userController.text = llm.userPrompt;
    }

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
          focusNode: _systemFocusNode,
          decoration: const InputDecoration(labelText: 'システムプロンプト'),
          maxLines: 6,
        ),
        const SizedBox(height: 16),
        TextFormField(
          key: const Key('userPromptField'),
          controller: _userController,
          focusNode: _userFocusNode,
          decoration: const InputDecoration(labelText: 'ユーザープロンプト'),
          maxLines: 6,
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
