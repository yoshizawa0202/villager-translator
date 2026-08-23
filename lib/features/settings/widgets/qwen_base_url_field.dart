import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../domain/llm/llm_provider.dart';
import '../../../domain/settings/settings_validator.dart';
import '../settings_controller.dart';

/// Qwen API ベース URL(任意)の入力欄
/// (`docs/specs/010-additional-llm-providers.md` §9、AC-15)。
///
/// Qwen を選択している場合だけ表示する。空欄なら国際向けエンドポイントを使い、
/// 入力がある場合は送信前に URL 形式を検証する。この値は Qwen アダプターへ
/// だけ渡り、他プロバイダーのアダプターへは渡らない
/// (`LlmSettings.toAdapterConfig()`)。
class QwenBaseUrlField extends StatefulWidget {
  const QwenBaseUrlField({super.key});

  @override
  State<QwenBaseUrlField> createState() => _QwenBaseUrlFieldState();
}

class _QwenBaseUrlFieldState extends State<QwenBaseUrlField> {
  late final TextEditingController _textController;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    final llm = context.read<SettingsController>().settings.llm;
    _textController = TextEditingController(text: llm.qwenBaseUrl);
    _focusNode = FocusNode()
      ..addListener(() {
        if (!_focusNode.hasFocus) {
          _save(_textController.text);
        }
      });
  }

  @override
  void dispose() {
    _textController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<SettingsController>();
    final llm = controller.settings.llm;

    if (llm.provider != LlmProvider.qwen) {
      return const SizedBox.shrink();
    }

    if (_textController.text != llm.qwenBaseUrl && !_focusNode.hasFocus) {
      _textController.text = llm.qwenBaseUrl;
    }

    return TextFormField(
      key: const Key('qwenBaseUrlField'),
      controller: _textController,
      focusNode: _focusNode,
      decoration: const InputDecoration(
        labelText: 'Qwen API ベース URL(任意)',
        helperText: '空欄の場合は国際向けエンドポイントを使用します',
      ),
      autovalidateMode: AutovalidateMode.onUserInteraction,
      validator: (value) => SettingsValidator.validateQwenBaseUrl(value ?? ''),
      onFieldSubmitted: _save,
    );
  }

  void _save(String value) {
    final controller = context.read<SettingsController>();
    if (controller.settings.llm.qwenBaseUrl == value) return;
    controller.updateLlm((s) => s.copyWith(qwenBaseUrl: value));
  }
}
