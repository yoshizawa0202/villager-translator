import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../domain/llm/llm_api_exception.dart';
import '../../../domain/llm/llm_provider.dart';
import '../settings_controller.dart';

/// 接続確認が成功したときの表示メッセージ。全対象プロバイダーで統一する
/// (`docs/specs/010-additional-llm-providers.md` §10、AC-16)。
const String kConnectionSuccessMessage = 'API接続に成功しました。';

/// API キー入力欄。表示/非表示切替アイコンと接続確認ボタンを持つ
/// (feature-spec.md §4.1、受け入れ条件4・11)。
class ApiKeyField extends StatefulWidget {
  const ApiKeyField({super.key});

  @override
  State<ApiKeyField> createState() => _ApiKeyFieldState();
}

class _ApiKeyFieldState extends State<ApiKeyField> {
  late final TextEditingController _textController;
  late final FocusNode _focusNode;
  bool _obscure = true;
  String? _testResultMessage;
  LlmProvider? _lastProvider;

  @override
  void initState() {
    super.initState();
    final controller = context.read<SettingsController>();
    final provider = controller.settings.llm.provider;
    _lastProvider = provider;
    _textController = TextEditingController(
      text: controller.apiKeyFor(provider),
    );
    _focusNode = FocusNode()
      ..addListener(() {
        if (!_focusNode.hasFocus) {
          final controller = context.read<SettingsController>();
          final currentProvider = controller.settings.llm.provider;
          final value = _textController.text;
          if (value == controller.apiKeyFor(currentProvider)) return;
          _save(context, currentProvider, value);
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
    final provider = controller.settings.llm.provider;

    if (_lastProvider != provider) {
      _lastProvider = provider;
      _textController.text = controller.apiKeyFor(provider);
      _testResultMessage = null;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: TextFormField(
                key: const Key('apiKeyField'),
                controller: _textController,
                focusNode: _focusNode,
                obscureText: _obscure,
                decoration: InputDecoration(
                  labelText: '${provider.displayName} API キー',
                  suffixIcon: IconButton(
                    key: const Key('apiKeyVisibilityToggle'),
                    icon: Icon(
                      _obscure ? Icons.visibility : Icons.visibility_off,
                    ),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                ),
                onFieldSubmitted: (value) => _save(context, provider, value),
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton(
              key: const Key('apiKeyTestButton'),
              onPressed: () => _testConnection(context, provider),
              child: const Text('接続確認'),
            ),
          ],
        ),
        if (_testResultMessage != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(_testResultMessage!),
          ),
      ],
    );
  }

  Future<void> _save(
    BuildContext context,
    LlmProvider provider,
    String value,
  ) async {
    await context.read<SettingsController>().setApiKey(provider, value);
  }

  Future<void> _testConnection(
    BuildContext context,
    LlmProvider provider,
  ) async {
    final controller = context.read<SettingsController>();
    final candidateApiKey = _textController.text;

    bool isValid;
    String message;
    try {
      isValid = await controller.testApiKey(provider, candidateApiKey);
      message = isValid ? kConnectionSuccessMessage : 'API接続に失敗しました。';
    } on LlmApiException catch (error) {
      // メッセージは HTTP 基底クラスで利用者向けの日本語へ変換済みで、
      // API キー・応答本文を含まない(010 §11)。
      isValid = false;
      message = error.message;
    }

    if (isValid) {
      await controller.setApiKey(provider, candidateApiKey);
    }
    if (!mounted) return;
    setState(() {
      _testResultMessage = message;
    });
  }
}
