import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../domain/llm/llm_provider.dart';
import '../settings_controller.dart';

/// LLM プロバイダー選択(feature-spec.md §4.1、受け入れ条件1)。
class ProviderSelector extends StatelessWidget {
  const ProviderSelector({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<SettingsController>();
    final current = controller.settings.llm.provider;

    return DropdownButtonFormField<LlmProvider>(
      key: const Key('providerSelector'),
      initialValue: current,
      decoration: const InputDecoration(labelText: 'プロバイダー'),
      items: LlmProvider.values
          .map((p) => DropdownMenuItem(value: p, child: Text(p.displayName)))
          .toList(),
      onChanged: (value) {
        if (value != null) {
          context.read<SettingsController>().setProvider(value);
        }
      },
    );
  }
}
