import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../domain/minecraftinstance/instance_analysis.dart';
import '../../domain/minecraftinstance/minecraft_instance.dart';
import '../../infrastructure/minecraftinstance/instance_analyzer.dart';
import '../instance_translation/instance_translation_page.dart';
import '../settings/settings_controller.dart';
import '../shell/main_shell_page.dart';
import '../shell/profile_directory_controller.dart';
import 'instance_analysis_controller.dart';

/// インスタンス選択後の解析結果画面
/// (011-launcher-instance-discovery.md §16)。
///
/// 解析結果を確認したうえで、一括翻訳([InstanceTranslationPage]、012)または
/// 従来の 4 タブ画面([MainShellPage])へ進む。
class InstanceDetailPage extends StatefulWidget {
  const InstanceDetailPage({
    super.key,
    required this.instance,
    this.controller,
    this.applicationSupportDirectory,
  });

  final MinecraftInstance instance;

  /// テスト用にコントローラーを直接注入するためのフック。
  final InstanceAnalysisController? controller;

  final Directory? applicationSupportDirectory;

  @override
  State<InstanceDetailPage> createState() => _InstanceDetailPageState();
}

class _InstanceDetailPageState extends State<InstanceDetailPage> {
  late final InstanceAnalysisController _controller;
  late final bool _ownsController;

  @override
  void initState() {
    super.initState();
    _ownsController = widget.controller == null;
    _controller =
        widget.controller ??
        InstanceAnalysisController(instance: widget.instance);
    if (_ownsController) _controller.analyze();
  }

  @override
  void dispose() {
    if (_ownsController) _controller.dispose();
    super.dispose();
  }

  /// 従来の 4 タブ画面へ遷移する(§13、§17)。
  ///
  /// `MinecraftInstance.rootPath` を既存の [ProfileDirectoryController] へ渡し、
  /// 4 タブすべてがそのディレクトリを対象として動作する状態にする。
  void _openTabbedShell() {
    final profileDirectoryController = ProfileDirectoryController()
      ..setPath(_controller.instance.rootPath);

    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => MainShellPage(
          instance: _controller.instance,
          profileDirectoryController: profileDirectoryController,
          applicationSupportDirectory: widget.applicationSupportDirectory,
        ),
      ),
    );
  }

  void _openBatchTranslation() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => InstanceTranslationPage(
          analysisController: _controller,
          applicationSupportDirectory: widget.applicationSupportDirectory,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<InstanceAnalysisController>.value(
      value: _controller,
      child: Consumer<InstanceAnalysisController>(
        builder: (context, controller, _) {
          final analysis = controller.analysis;

          return Scaffold(
            appBar: AppBar(title: Text(controller.instance.name)),
            body: switch (controller.state) {
              InstanceAnalysisState.idle || InstanceAnalysisState.analyzing =>
                _AnalysisProgress(controller: controller),
              InstanceAnalysisState.failed => _AnalysisError(
                controller: controller,
              ),
              InstanceAnalysisState.analyzed => _AnalysisResult(
                analysis: analysis!,
                controller: controller,
                onOpenBatchTranslation: _openBatchTranslation,
                onOpenTabbedShell: _openTabbedShell,
              ),
            },
          );
        },
      ),
    );
  }
}

/// 解析中の進捗表示とキャンセル(§16)。
class _AnalysisProgress extends StatelessWidget {
  const _AnalysisProgress({required this.controller});

  final InstanceAnalysisController controller;

  static const Map<InstanceAnalysisStage, String> _stageLabels = {
    InstanceAnalysisStage.mods: 'MOD を解析しています...',
    InstanceAnalysisStage.quests: 'クエストを解析しています...',
    InstanceAnalysisStage.guidebooks: 'ガイドブックを解析しています...',
  };

  @override
  Widget build(BuildContext context) {
    return Center(
      key: const Key('instanceAnalysisProgress'),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 12),
          Text(
            _stageLabels[controller.stage] ?? '翻訳対象を解析しています...',
            key: const Key('instanceAnalysisStageLabel'),
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            key: const Key('cancelInstanceAnalysisButton'),
            onPressed: controller.isCancelling ? null : controller.cancel,
            child: Text(controller.isCancelling ? 'キャンセル中...' : 'キャンセル'),
          ),
        ],
      ),
    );
  }
}

/// 解析失敗時の表示(インスタンスが削除されていた場合を含む、AC-21)。
class _AnalysisError extends StatelessWidget {
  const _AnalysisError({required this.controller});

  final InstanceAnalysisController controller;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              controller.errorMessage ?? 'インスタンスの解析に失敗しました。',
              key: const Key('instanceAnalysisErrorMessage'),
              textAlign: TextAlign.center,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              key: const Key('backToInstanceListButton'),
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('一覧へ戻る'),
            ),
          ],
        ),
      ),
    );
  }
}

/// 解析結果の表示(§16)。
///
/// 新しい判定ロジックは持たず、[InstanceAnalysis] が既存スキャン結果から
/// 導出した内訳をそのまま表示する。
class _AnalysisResult extends StatelessWidget {
  const _AnalysisResult({
    required this.analysis,
    required this.controller,
    required this.onOpenBatchTranslation,
    required this.onOpenTabbedShell,
  });

  final InstanceAnalysis analysis;
  final InstanceAnalysisController controller;
  final VoidCallback onOpenBatchTranslation;
  final VoidCallback onOpenTabbedShell;

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsController>().settings;
    final instance = controller.instance;

    return ListView(
      key: const Key('instanceAnalysisResult'),
      padding: const EdgeInsets.all(16),
      children: [
        DropdownButtonFormField<String>(
          key: const Key('instanceTargetLanguageSelector'),
          initialValue: controller.targetLanguageId,
          decoration: const InputDecoration(labelText: '対象言語'),
          items: settings.translation.allLanguages
              .map(
                (l) =>
                    DropdownMenuItem(value: l.id, child: Text(l.displayName)),
              )
              .toList(),
          onChanged: (value) {
            if (value != null) controller.setTargetLanguageId(value);
          },
        ),
        const SizedBox(height: 16),
        _SummaryTile(
          label: 'Minecraft',
          value: instance.minecraftVersionLabel,
          valueKey: const Key('analysisMinecraftVersion'),
        ),
        _SummaryTile(
          label: 'Loader',
          value: instance.modLoader.displayName,
          valueKey: const Key('analysisModLoader'),
        ),
        const Divider(height: 32),
        Text('MOD', style: Theme.of(context).textTheme.titleMedium),
        _SummaryTile(
          label: 'MOD',
          value: '${analysis.modJarCount} 個',
          valueKey: const Key('analysisModJarCount'),
        ),
        _SummaryTile(
          label: '翻訳可能MOD',
          value: '${analysis.translatableModCount} 個',
          valueKey: const Key('analysisTranslatableModCount'),
        ),
        _SummaryTile(
          label: '翻訳済み',
          value: '${analysis.translatedModCount} 個',
          valueKey: const Key('analysisTranslatedModCount'),
        ),
        _SummaryTile(
          label: '未翻訳',
          value: '${analysis.untranslatedModCount} 個',
          valueKey: const Key('analysisUntranslatedModCount'),
        ),
        const Divider(height: 32),
        Text('クエスト', style: Theme.of(context).textTheme.titleMedium),
        for (final summary in analysis.questSummaries)
          ListTile(
            key: Key('analysisQuestFamily_${summary.family.name}'),
            dense: true,
            leading: Icon(
              summary.detected ? Icons.check : Icons.remove,
              color: summary.detected
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).disabledColor,
            ),
            title: Text(summary.family.displayName),
            subtitle: Text(
              summary.detected
                  ? '${summary.fileCount} ファイル / ${summary.stringCount} 文字列'
                  : '未検出',
            ),
          ),
        const Divider(height: 32),
        Text('ガイドブック', style: Theme.of(context).textTheme.titleMedium),
        if (analysis.guidebooks.isEmpty)
          const ListTile(
            key: Key('analysisNoGuidebooks'),
            dense: true,
            title: Text('未検出'),
          )
        else ...[
          _SummaryTile(
            label: 'Patchouli',
            value: '${analysis.guidebooks.length} 冊',
            valueKey: const Key('analysisGuidebookCount'),
          ),
          for (final book in analysis.guidebooks)
            ListTile(
              key: Key('analysisGuidebook_${book.bookKey}'),
              dense: true,
              title: Text(book.modId),
              subtitle: Text(book.bookId),
              trailing: Text(book.hasExistingTranslation ? '翻訳済み' : '未翻訳'),
            ),
        ],
        const SizedBox(height: 24),
        FilledButton(
          key: const Key('openBatchTranslationButton'),
          onPressed: analysis.isEmpty ? null : onOpenBatchTranslation,
          child: const Text('一括翻訳へ進む'),
        ),
        const SizedBox(height: 8),
        OutlinedButton(
          key: const Key('openTabbedShellButton'),
          onPressed: onOpenTabbedShell,
          child: const Text('個別に選んで翻訳する(4タブ画面)'),
        ),
      ],
    );
  }
}

class _SummaryTile extends StatelessWidget {
  const _SummaryTile({
    required this.label,
    required this.value,
    required this.valueKey,
  });

  final String label;
  final String value;
  final Key valueKey;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(width: 160, child: Text(label)),
          Text(value, key: valueKey),
        ],
      ),
    );
  }
}
