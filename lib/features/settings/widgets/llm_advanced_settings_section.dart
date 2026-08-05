import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../domain/settings/settings_validator.dart';
import '../settings_controller.dart';

/// 最大リトライ回数・temperature の詳細設定(feature-spec.md §4.1、受け入れ条件3)。
class LlmAdvancedSettingsSection extends StatefulWidget {
  const LlmAdvancedSettingsSection({super.key});

  @override
  State<LlmAdvancedSettingsSection> createState() =>
      _LlmAdvancedSettingsSectionState();
}

class _LlmAdvancedSettingsSectionState
    extends State<LlmAdvancedSettingsSection> {
  late final TextEditingController _maxRetriesController;
  late final TextEditingController _temperatureController;
  late final FocusNode _maxRetriesFocusNode;
  late final FocusNode _temperatureFocusNode;

  @override
  void initState() {
    super.initState();
    final llm = context.read<SettingsController>().settings.llm;
    _maxRetriesController = TextEditingController(
      text: llm.maxRetries.toString(),
    );
    _temperatureController = TextEditingController(
      text: llm.temperature.toString(),
    );
    _maxRetriesFocusNode = FocusNode()
      ..addListener(() {
        if (!_maxRetriesFocusNode.hasFocus) {
          _saveMaxRetries(context, _maxRetriesController.text);
        }
      });
    _temperatureFocusNode = FocusNode()
      ..addListener(() {
        if (!_temperatureFocusNode.hasFocus) {
          _saveTemperature(context, _temperatureController.text);
        }
      });
  }

  @override
  void dispose() {
    _maxRetriesController.dispose();
    _temperatureController.dispose();
    _maxRetriesFocusNode.dispose();
    _temperatureFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<SettingsController>();
    final llm = controller.settings.llm;

    final maxRetriesText = llm.maxRetries.toString();
    if (_maxRetriesController.text != maxRetriesText) {
      _maxRetriesController.text = maxRetriesText;
    }
    final temperatureText = llm.temperature.toString();
    if (_temperatureController.text != temperatureText) {
      _temperatureController.text = temperatureText;
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: TextFormField(
            key: const Key('maxRetriesField'),
            controller: _maxRetriesController,
            focusNode: _maxRetriesFocusNode,
            decoration: const InputDecoration(labelText: '最大リトライ回数'),
            keyboardType: TextInputType.number,
            autovalidateMode: AutovalidateMode.onUserInteraction,
            validator: (value) {
              final parsed = int.tryParse(value ?? '');
              if (parsed == null) return '整数を入力してください';
              return SettingsValidator.validateMaxRetries(parsed);
            },
            onFieldSubmitted: (value) => _saveMaxRetries(context, value),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: TextFormField(
            key: const Key('temperatureField'),
            controller: _temperatureController,
            focusNode: _temperatureFocusNode,
            decoration: const InputDecoration(labelText: 'temperature'),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            autovalidateMode: AutovalidateMode.onUserInteraction,
            validator: (value) {
              final parsed = double.tryParse(value ?? '');
              if (parsed == null) return '数値を入力してください';
              return SettingsValidator.validateTemperature(parsed);
            },
            onFieldSubmitted: (value) => _saveTemperature(context, value),
          ),
        ),
      ],
    );
  }

  void _saveMaxRetries(BuildContext context, String value) {
    final parsed = int.tryParse(value);
    if (parsed == null) return;
    context.read<SettingsController>().updateLlm(
      (s) => s.copyWith(maxRetries: parsed),
    );
  }

  void _saveTemperature(BuildContext context, String value) {
    final parsed = double.tryParse(value);
    if (parsed == null) return;
    context.read<SettingsController>().updateLlm(
      (s) => s.copyWith(temperature: parsed),
    );
  }
}
