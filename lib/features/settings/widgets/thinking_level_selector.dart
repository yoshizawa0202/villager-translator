import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../domain/llm/thinking_level.dart';
import '../settings_controller.dart';

/// 思考量(reasoning effort / extended thinking)選択コンボボックス
/// (`docs/specs/009-thinking-level-setting.md`、
/// `docs/specs/010-additional-llm-providers.md` AC-06)。
///
/// 選択肢はモデル能力情報([ModelCapabilities])から導出し、選択中モデルで
/// 利用できないレベルは一覧に表示しない。思考量に対応しないモデルでは選択自体を
/// 無効化し、対応していない旨を注記する。
class ThinkingLevelSelector extends StatelessWidget {
  const ThinkingLevelSelector({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<SettingsController>();
    final llm = controller.settings.llm;
    final capabilities = llm.capabilities;
    final supportedLevels = capabilities.thinkingLevels;
    final supportsThinking = capabilities.supportsThinking;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButtonFormField<ThinkingLevel>(
          key: const Key('thinkingLevelSelector'),
          initialValue: supportedLevels.contains(llm.thinkingLevel)
              ? llm.thinkingLevel
              : null,
          decoration: const InputDecoration(labelText: '思考量'),
          items: supportedLevels
              .map(
                (level) => DropdownMenuItem(
                  value: level,
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
