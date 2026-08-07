import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../domain/llm/model_catalog.dart';
import '../../../domain/llm/thinking_level.dart';
import '../settings_controller.dart';

/// 思考量(reasoning effort / extended thinking)選択コンボボックス
/// (`docs/specs/009-thinking-level-setting.md`)。
///
/// 選択中モデルが思考量に対応していない場合は [ThinkingLevel.off] 以外を
/// 選択不可にし、対応していない旨を注記する。
class ThinkingLevelSelector extends StatelessWidget {
  const ThinkingLevelSelector({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<SettingsController>();
    final llm = controller.settings.llm;
    final info = modelInfoFor(llm.provider, llm.model);

    // カスタムモデル・未知のモデルは対応可否が不明なため制限しない。
    final supportedLevels = llm.model == kCustomModelSentinel || info == null
        ? ThinkingLevel.values
        : info.supportedThinkingLevels;
    final supportsThinking = supportedLevels.any(
      (level) => level != ThinkingLevel.off,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButtonFormField<ThinkingLevel>(
          key: const Key('thinkingLevelSelector'),
          initialValue: llm.thinkingLevel,
          decoration: const InputDecoration(labelText: '思考量'),
          items: ThinkingLevel.values
              .map(
                (level) => DropdownMenuItem(
                  value: level,
                  enabled: supportedLevels.contains(level),
                  child: Text(level.displayName),
                ),
              )
              .toList(),
          onChanged: supportsThinking
              ? (value) {
                  if (value != null) {
                    controller.updateLlm(
                      (s) => s.copyWith(thinkingLevel: value),
                    );
                  }
                }
              : null,
        ),
        if (!supportsThinking)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'このモデルは思考量の設定に対応していません',
              key: const Key('thinkingLevelUnsupportedNotice'),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.error,
              ),
            ),
          ),
      ],
    );
  }
}
