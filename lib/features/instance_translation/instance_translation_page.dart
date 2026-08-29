import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../domain/instancetranslation/instance_translation_mode.dart';
import '../../domain/instancetranslation/instance_translation_outcome.dart';
import '../../domain/llm/llm_provider.dart';
import '../../domain/llm/model_catalog.dart';
import '../instance_detail/instance_analysis_controller.dart';
import '../settings/settings_controller.dart';
import '../shell/widgets/cancel_confirmation_dialog.dart';
import '../shell/widgets/log_viewer_dialog.dart';
import 'instance_translation_controller.dart';
import 'widgets/instance_translation_completion_dialog.dart';
import 'widgets/instance_translation_progress_panel.dart';
import 'widgets/instance_translation_summary_dialog.dart';

/// インスタンス一括翻訳画面(012-instance-batch-translation.md §3〜§12)。
///
/// 翻訳対象・対象言語・LLM モデル・翻訳モードを 1 画面で指定し、
/// 「すべて翻訳」で翻訳前サマリーを確認したうえで実行する。
class InstanceTranslationPage extends StatefulWidget {
  const InstanceTranslationPage({
    super.key,
    required this.analysisController,
    this.controller,
    this.applicationSupportDirectory,
  });

  /// 解析結果の提供元。対象言語を変更したときは再解析する(011 §16)。
  final InstanceAnalysisController analysisController;

  /// テスト用にコントローラーを直接注入するためのフック。
  final InstanceTranslationController? controller;

  final Directory? applicationSupportDirectory;

  @override
  State<InstanceTranslationPage> createState() =>
      _InstanceTranslationPageState();
}

class _InstanceTranslationPageState extends State<InstanceTranslationPage> {
  late final InstanceTranslationController _controller;
  late final bool _ownsController;
  InstanceTranslationOutcome? _lastShownOutcome;

  @override
  void initState() {
    super.initState();
    _ownsController = widget.controller == null;
    _controller =
        widget.controller ??
        InstanceTranslationController(
          settingsController: context.read<SettingsController>(),
          analysis: widget.analysisController.analysis!,
          targetLanguageId: widget.analysisController.targetLanguageId,
          applicationSupportDirectory: widget.applicationSupportDirectory,
        );
    _controller.addListener(_onControllerChanged);
    widget.analysisController.addListener(_onAnalysisChanged);
  }

  @override
  void dispose() {
    widget.analysisController.removeListener(_onAnalysisChanged);
    _controller.removeListener(_onControllerChanged);
    if (_ownsController) _controller.dispose();
    super.dispose();
  }

  /// 対象言語の変更で再解析された結果を取り込む(既存翻訳の判定が変わるため)。
  void _onAnalysisChanged() {
    final analysis = widget.analysisController.analysis;
    if (analysis != null) _controller.updateAnalysis(analysis);
  }

  void _onControllerChanged() {
    if (!mounted) return;
    final outcome = _controller.lastOutcome;
    if (_controller.state == InstanceTranslationState.completed &&
        outcome != null &&
        !identical(outcome, _lastShownOutcome)) {
      _lastShownOutcome = outcome;
      InstanceTranslationCompletionDialog.show(
        context,
        outcome: outcome,
        onShowLog: () => LogViewerDialog.show(
          context,
          logger: _controller.sessionLogger,
          isBusy: false,
        ),
        onRetryFailed: _controller.retryFailed,
      );
    }
  }

  /// 「すべて翻訳」。実行前に必ず翻訳前サマリーを表示する(§6、AC-06)。
  Future<void> _startTranslation() async {
    final settings = context.read<SettingsController>().settings;
    final language = settings.translation.allLanguages
        .where((l) => l.id == _controller.targetLanguageId)
        .map((l) => l.displayName)
        .firstOrNull;

    final confirmed = await InstanceTranslationSummaryDialog.show(
      context,
      instanceName: _controller.analysis.instance.name,
      estimate: _controller.buildEstimate(),
      modelLabel: '${_controller.provider.displayName} / ${_controller.model}',
      languageLabel: language ?? _controller.targetLanguageId,
      modeLabel: _controller.mode.displayName,
    );
    if (!confirmed) return;

    await _controller.translate();
  }

  Future<void> _cancelTranslation() async {
    final confirmed = await CancelConfirmationDialog.show(context);
    if (confirmed) _controller.cancel();
  }

  @override
  Widget build(BuildContext context) {
    // 新しいルートとして push されるため、解析コントローラーもこの画面で
    // 提供し直す(対象言語の変更で再解析するのに必要、011 §16)。
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<InstanceAnalysisController>.value(
          value: widget.analysisController,
        ),
        ChangeNotifierProvider<InstanceTranslationController>.value(
          value: _controller,
        ),
      ],
      child: Consumer<InstanceTranslationController>(
        builder: (context, controller, _) {
          return Scaffold(
            appBar: AppBar(
              title: Text('${controller.analysis.instance.name} を一括翻訳'),
            ),
            body: controller.state == InstanceTranslationState.translating
                ? Padding(
                    padding: const EdgeInsets.all(16),
                    child: InstanceTranslationProgressPanel(
                      instanceName: controller.analysis.instance.name,
                      categoryProgress: {
                        for (final category
                            in InstanceTranslationCategory.values)
                          category: controller.progressFor(category),
                      },
                      overallProgress: controller.overallProgress,
                      singleFileProgress: controller.singleFileProgress,
                      currentItemName: controller.currentItemName,
                      onCancel: _cancelTranslation,
                      isCancelling: controller.isCancelling,
                    ),
                  )
                : _TranslationSetupView(onStart: _startTranslation),
          );
        },
      ),
    );
  }
}

/// 翻訳対象・対象言語・モデル・翻訳モードの指定(§3〜§5)。
class _TranslationSetupView extends StatelessWidget {
  const _TranslationSetupView({required this.onStart});

  final Future<void> Function() onStart;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<InstanceTranslationController>();
    final settings = context.watch<SettingsController>().settings;
    final analysis = controller.analysis;
    final packFormat = controller.packFormat;

    return ListView(
      key: const Key('instanceTranslationSetup'),
      padding: const EdgeInsets.all(16),
      children: [
        Text('翻訳対象', style: Theme.of(context).textTheme.titleMedium),
        _CategoryCheckbox(
          checkboxKey: const Key('translateModsCheckbox'),
          label: 'MOD',
          detail: analysis.mods.isEmpty
              ? '未検出'
              : '${analysis.translatableModCount} 個'
                    '(翻訳済み ${analysis.translatedModCount} / '
                    '未翻訳 ${analysis.untranslatedModCount})',
          value: controller.translateMods,
          enabled: analysis.mods.isNotEmpty,
          onChanged: controller.setTranslateMods,
        ),
        _CategoryCheckbox(
          checkboxKey: const Key('translateQuestsCheckbox'),
          label: 'クエスト',
          detail: analysis.quests.isEmpty
              ? '未検出'
              : analysis.questSummaries
                    .where((s) => s.detected)
                    .map((s) => s.family.displayName)
                    .join(' / '),
          value: controller.translateQuests,
          enabled: analysis.quests.isNotEmpty,
          onChanged: controller.setTranslateQuests,
        ),
        _CategoryCheckbox(
          checkboxKey: const Key('translateGuidebooksCheckbox'),
          label: 'ガイドブック',
          detail: analysis.guidebooks.isEmpty
              ? '未検出'
              : '${analysis.guidebooks.length} 冊'
                    '(翻訳済み ${analysis.translatedGuidebookCount} / '
                    '未翻訳 ${analysis.untranslatedGuidebookCount})',
          value: controller.translateGuidebooks,
          enabled: analysis.guidebooks.isNotEmpty,
          onChanged: controller.setTranslateGuidebooks,
        ),
        const Divider(height: 32),
        DropdownButtonFormField<String>(
          key: const Key('instanceTranslationLanguageSelector'),
          initialValue: controller.targetLanguageId,
          decoration: const InputDecoration(labelText: '対象言語'),
          items: settings.translation.allLanguages
              .map(
                (l) =>
                    DropdownMenuItem(value: l.id, child: Text(l.displayName)),
              )
              .toList(),
          onChanged: (value) {
            if (value == null) return;
            controller.setTargetLanguageId(value);
            // 既存翻訳の判定結果が変わるため、解析もやり直す(011 §16)。
            context.read<InstanceAnalysisController>().setTargetLanguageId(
              value,
            );
          },
        ),
        const SizedBox(height: 12),
        const _ProviderAndModelSelectors(),
        const SizedBox(height: 12),
        DropdownButtonFormField<InstanceTranslationMode>(
          key: const Key('instanceTranslationModeSelector'),
          initialValue: controller.mode,
          decoration: const InputDecoration(labelText: '翻訳モード'),
          items: InstanceTranslationMode.values
              .map(
                (m) => DropdownMenuItem(value: m, child: Text(m.displayName)),
              )
              .toList(),
          onChanged: (value) {
            if (value != null) controller.setMode(value);
          },
        ),
        const SizedBox(height: 12),
        Text(
          'リソースパック仕様 pack_format: ${packFormat.packFormat}'
          '${packFormat.isEstimated ? '(推定値: 対応表より新しい Minecraft バージョンです)' : ''}'
          '${packFormat.isFallback ? '(既定値: Minecraft バージョンを判定できませんでした)' : ''}',
          key: const Key('instancePackFormatLabel'),
        ),
        if (controller.errorMessage != null) ...[
          const SizedBox(height: 12),
          Text(
            controller.errorMessage!,
            key: const Key('instanceTranslationErrorMessage'),
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
        const SizedBox(height: 24),
        FilledButton(
          key: const Key('translateAllButton'),
          onPressed: controller.canTranslate ? onStart : null,
          child: const Text('すべて翻訳'),
        ),
      ],
    );
  }
}

class _CategoryCheckbox extends StatelessWidget {
  const _CategoryCheckbox({
    required this.checkboxKey,
    required this.label,
    required this.detail,
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final Key checkboxKey;
  final String label;
  final String detail;
  final bool value;

  /// 0 件のカテゴリは操作不可にする(§3、AC-02)。
  final bool enabled;

  final void Function(bool value) onChanged;

  @override
  Widget build(BuildContext context) {
    return CheckboxListTile(
      key: checkboxKey,
      value: value,
      title: Text(label),
      subtitle: Text(detail),
      onChanged: enabled ? (v) => onChanged(v ?? false) : null,
    );
  }
}

/// プロバイダーとモデルの選択(§4)。
///
/// 選択肢は既存のモデルカタログ([kModelCatalog])から導出し、この画面が独自の
/// モデル一覧を持たない(AC-05)。
class _ProviderAndModelSelectors extends StatelessWidget {
  const _ProviderAndModelSelectors();

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<InstanceTranslationController>();
    final models = (kModelCatalog[controller.provider] ?? const <ModelInfo>[])
        .map((info) => info.id)
        .toList();

    return Row(
      children: [
        Expanded(
          child: DropdownButtonFormField<LlmProvider>(
            key: const Key('instanceTranslationProviderSelector'),
            initialValue: controller.provider,
            decoration: const InputDecoration(labelText: 'プロバイダー'),
            items: LlmProvider.values
                .map(
                  (p) => DropdownMenuItem(value: p, child: Text(p.displayName)),
                )
                .toList(),
            onChanged: (value) {
              if (value != null) controller.setProvider(value);
            },
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: DropdownButtonFormField<String>(
            key: const Key('instanceTranslationModelSelector'),
            // 保存済み設定がカスタムモデルの場合はカタログに無いため、
            // 選択なし(ヒント表示)として扱う。
            initialValue: models.contains(controller.model)
                ? controller.model
                : null,
            decoration: InputDecoration(
              labelText: 'モデル',
              hintText: controller.model,
            ),
            items: models
                .map((m) => DropdownMenuItem(value: m, child: Text(m)))
                .toList(),
            onChanged: (value) {
              if (value != null) controller.setModel(value);
            },
          ),
        ),
      ],
    );
  }
}
