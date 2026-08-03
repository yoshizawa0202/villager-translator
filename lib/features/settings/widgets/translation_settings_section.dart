import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../domain/settings/existing_translation_policy.dart';
import '../../../domain/settings/settings_validator.dart';
import '../../../domain/settings/translation_settings.dart';
import '../settings_controller.dart';

/// 翻訳設定(チャンク分割・既存翻訳の扱い・リソースパック名・カテゴリ別チャンクサイズ)
/// (feature-spec.md §4.2)。
class TranslationSettingsSection extends StatefulWidget {
  const TranslationSettingsSection({super.key});

  @override
  State<TranslationSettingsSection> createState() =>
      _TranslationSettingsSectionState();
}

class _TranslationSettingsSectionState
    extends State<TranslationSettingsSection> {
  late final TextEditingController _maxTokensController;
  late final TextEditingController _resourcePackNameController;
  late final TextEditingController _modChunkSizeController;
  late final TextEditingController _questChunkSizeController;
  late final TextEditingController _guidebookChunkSizeController;

  @override
  void initState() {
    super.initState();
    final t = context.read<SettingsController>().settings.translation;
    _maxTokensController = TextEditingController(
      text: t.maxTokensPerChunk.toString(),
    );
    _resourcePackNameController = TextEditingController(
      text: t.resourcePackName,
    );
    _modChunkSizeController = TextEditingController(
      text: t.modChunkSize.toString(),
    );
    _questChunkSizeController = TextEditingController(
      text: t.questChunkSize.toString(),
    );
    _guidebookChunkSizeController = TextEditingController(
      text: t.guidebookChunkSize.toString(),
    );
  }

  @override
  void dispose() {
    _maxTokensController.dispose();
    _resourcePackNameController.dispose();
    _modChunkSizeController.dispose();
    _questChunkSizeController.dispose();
    _guidebookChunkSizeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<SettingsController>();
    final t = controller.settings.translation;

    final maxTokensText = t.maxTokensPerChunk.toString();
    if (_maxTokensController.text != maxTokensText) {
      _maxTokensController.text = maxTokensText;
    }
    if (_resourcePackNameController.text != t.resourcePackName) {
      _resourcePackNameController.text = t.resourcePackName;
    }
    final modChunkSizeText = t.modChunkSize.toString();
    if (_modChunkSizeController.text != modChunkSizeText) {
      _modChunkSizeController.text = modChunkSizeText;
    }
    final questChunkSizeText = t.questChunkSize.toString();
    if (_questChunkSizeController.text != questChunkSizeText) {
      _questChunkSizeController.text = questChunkSizeText;
    }
    final guidebookChunkSizeText = t.guidebookChunkSize.toString();
    if (_guidebookChunkSizeController.text != guidebookChunkSizeText) {
      _guidebookChunkSizeController.text = guidebookChunkSizeText;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SwitchListTile(
          key: const Key('tokenBasedChunkingSwitch'),
          title: const Text('トークンベースのチャンク分割'),
          value: t.useTokenBasedChunking,
          onChanged: (value) {
            context.read<SettingsController>().updateTranslation(
              (s) => s.copyWith(useTokenBasedChunking: value),
            );
          },
        ),
        TextFormField(
          key: const Key('maxTokensPerChunkField'),
          controller: _maxTokensController,
          decoration: const InputDecoration(labelText: 'チャンクあたり最大トークン数'),
          keyboardType: TextInputType.number,
          enabled: t.useTokenBasedChunking,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          validator: (value) {
            final parsed = int.tryParse(value ?? '');
            if (parsed == null) return '整数を入力してください';
            return SettingsValidator.validateMaxTokensPerChunk(parsed);
          },
          onFieldSubmitted: (value) => _saveInt(
            context,
            value,
            (s, v) => s.copyWith(maxTokensPerChunk: v),
          ),
          onEditingComplete: () => _saveInt(
            context,
            _maxTokensController.text,
            (s, v) => s.copyWith(maxTokensPerChunk: v),
          ),
        ),
        SwitchListTile(
          key: const Key('fallbackToEntryBasedSwitch'),
          title: const Text('見積り失敗時にエントリ数ベースへフォールバックする'),
          value: t.fallbackToEntryBased,
          onChanged: (value) {
            context.read<SettingsController>().updateTranslation(
              (s) => s.copyWith(fallbackToEntryBased: value),
            );
          },
        ),
        DropdownButtonFormField<ExistingTranslationPolicy>(
          key: const Key('existingTranslationPolicySelector'),
          initialValue: t.existingTranslationPolicy,
          decoration: const InputDecoration(labelText: '既存翻訳の扱い'),
          items: const [
            DropdownMenuItem(
              value: ExistingTranslationPolicy.skip,
              child: Text('スキップ'),
            ),
            DropdownMenuItem(
              value: ExistingTranslationPolicy.diffUpdate,
              child: Text('差分更新'),
            ),
            DropdownMenuItem(
              value: ExistingTranslationPolicy.retranslateAll,
              child: Text('全て再翻訳'),
            ),
          ],
          onChanged: (value) {
            if (value != null) {
              context.read<SettingsController>().updateTranslation(
                (s) => s.copyWith(existingTranslationPolicy: value),
              );
            }
          },
        ),
        TextFormField(
          key: const Key('resourcePackNameField'),
          controller: _resourcePackNameController,
          decoration: const InputDecoration(labelText: 'リソースパック名'),
          onFieldSubmitted: (value) => context
              .read<SettingsController>()
              .updateTranslation((s) => s.copyWith(resourcePackName: value)),
          onEditingComplete: () =>
              context.read<SettingsController>().updateTranslation(
                (s) => s.copyWith(
                  resourcePackName: _resourcePackNameController.text,
                ),
              ),
        ),
        Row(
          children: [
            Expanded(
              child: TextFormField(
                key: const Key('modChunkSizeField'),
                controller: _modChunkSizeController,
                decoration: const InputDecoration(labelText: 'MOD チャンクサイズ'),
                keyboardType: TextInputType.number,
                autovalidateMode: AutovalidateMode.onUserInteraction,
                validator: (value) {
                  final parsed = int.tryParse(value ?? '');
                  if (parsed == null) return '整数を入力してください';
                  return SettingsValidator.validateChunkSize(parsed);
                },
                onFieldSubmitted: (value) => _saveInt(
                  context,
                  value,
                  (s, v) => s.copyWith(modChunkSize: v),
                ),
                onEditingComplete: () => _saveInt(
                  context,
                  _modChunkSizeController.text,
                  (s, v) => s.copyWith(modChunkSize: v),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextFormField(
                key: const Key('questChunkSizeField'),
                controller: _questChunkSizeController,
                decoration: const InputDecoration(labelText: 'クエスト チャンクサイズ'),
                keyboardType: TextInputType.number,
                autovalidateMode: AutovalidateMode.onUserInteraction,
                validator: (value) {
                  final parsed = int.tryParse(value ?? '');
                  if (parsed == null) return '整数を入力してください';
                  return SettingsValidator.validateChunkSize(parsed);
                },
                onFieldSubmitted: (value) => _saveInt(
                  context,
                  value,
                  (s, v) => s.copyWith(questChunkSize: v),
                ),
                onEditingComplete: () => _saveInt(
                  context,
                  _questChunkSizeController.text,
                  (s, v) => s.copyWith(questChunkSize: v),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextFormField(
                key: const Key('guidebookChunkSizeField'),
                controller: _guidebookChunkSizeController,
                decoration: const InputDecoration(labelText: 'ガイドブック チャンクサイズ'),
                keyboardType: TextInputType.number,
                autovalidateMode: AutovalidateMode.onUserInteraction,
                validator: (value) {
                  final parsed = int.tryParse(value ?? '');
                  if (parsed == null) return '整数を入力してください';
                  return SettingsValidator.validateChunkSize(parsed);
                },
                onFieldSubmitted: (value) => _saveInt(
                  context,
                  value,
                  (s, v) => s.copyWith(guidebookChunkSize: v),
                ),
                onEditingComplete: () => _saveInt(
                  context,
                  _guidebookChunkSizeController.text,
                  (s, v) => s.copyWith(guidebookChunkSize: v),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  void _saveInt(
    BuildContext context,
    String value,
    TranslationSettings Function(TranslationSettings s, int v) apply,
  ) {
    final parsed = int.tryParse(value);
    if (parsed == null) return;
    context.read<SettingsController>().updateTranslation(
      (s) => apply(s, parsed),
    );
  }
}
