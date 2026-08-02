import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../domain/llm/model_catalog.dart';
import '../../../domain/settings/settings_validator.dart';
import '../settings_controller.dart';

/// モデル選択コンボボックス。一覧にない値は「カスタム」で自由入力できる
/// (feature-spec.md §4.1、受け入れ条件2)。
class ModelSelector extends StatefulWidget {
  const ModelSelector({super.key});

  @override
  State<ModelSelector> createState() => _ModelSelectorState();
}

class _ModelSelectorState extends State<ModelSelector> {
  late final TextEditingController _customModelController;
  String? _selectedModel;

  @override
  void initState() {
    super.initState();
    final llm = context.read<SettingsController>().settings.llm;
    _customModelController = TextEditingController(text: llm.customModel);
    _selectedModel = llm.model;
  }

  @override
  void dispose() {
    _customModelController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<SettingsController>();
    final llm = controller.settings.llm;
    final candidates = kModelCatalog[llm.provider] ?? const [];
    final selectedModel = _selectedModel ?? llm.model;
    final isCustom = selectedModel == kCustomModelSentinel;

    if (llm.model != kCustomModelSentinel && _selectedModel != llm.model) {
      _selectedModel = llm.model;
    }

    if (_customModelController.text != llm.customModel) {
      _customModelController.text = llm.customModel;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButtonFormField<String>(
          key: const Key('modelSelector'),
          initialValue: candidates.contains(selectedModel) || isCustom
              ? (isCustom ? kCustomModelSentinel : selectedModel)
              : null,
          decoration: const InputDecoration(labelText: 'モデル'),
          items: [
            ...candidates.map(
              (m) => DropdownMenuItem(value: m, child: Text(m)),
            ),
            const DropdownMenuItem(
              value: kCustomModelSentinel,
              child: Text('カスタム'),
            ),
          ],
          onChanged: (value) {
            if (value != null) {
              setState(() {
                _selectedModel = value;
              });
              if (value != kCustomModelSentinel) {
                context.read<SettingsController>().updateLlm(
                  (s) => s.copyWith(model: value, customModel: ''),
                );
              }
            }
          },
        ),
        if (isCustom)
          TextFormField(
            key: const Key('customModelField'),
            controller: _customModelController,
            decoration: const InputDecoration(labelText: 'カスタムモデル名'),
            autovalidateMode: AutovalidateMode.onUserInteraction,
            validator: (value) => SettingsValidator.validateCustomModel(
              kCustomModelSentinel,
              value ?? '',
            ),
            onFieldSubmitted: (value) {
              context.read<SettingsController>().updateLlm(
                (s) => s.copyWith(
                  model: kCustomModelSentinel,
                  customModel: value,
                ),
              );
            },
            onEditingComplete: () {
              context.read<SettingsController>().updateLlm(
                (s) => s.copyWith(
                  model: kCustomModelSentinel,
                  customModel: _customModelController.text,
                ),
              );
            },
          ),
      ],
    );
  }
}
