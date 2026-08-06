import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../infrastructure/questtranslation/quest_translation_orchestrator.dart';
import '../settings/settings_controller.dart';
import '../shell/widgets/log_viewer_dialog.dart';
import '../shell/widgets/translation_completion_dialog.dart';
import '../shell/widgets/translation_progress_panel.dart';
import 'quest_translation_controller.dart';

/// クエストタブ画面(feature-spec.md §7)。
///
/// プロファイルディレクトリ選択・スキャン・対象言語選択・テーブル
/// (チェックボックス・ソート・部分一致検索)・翻訳実行を提供する。
class QuestTranslationPage extends StatelessWidget {
  const QuestTranslationPage({super.key, this.controller});

  /// テスト用にコントローラーを直接注入するためのフック。
  /// 通常利用時は `null` のままで、画面が自前で生成する。
  final QuestTranslationController? controller;

  @override
  Widget build(BuildContext context) {
    if (controller != null) {
      return ChangeNotifierProvider<QuestTranslationController>.value(
        value: controller!,
        child: Scaffold(
          appBar: AppBar(title: const Text('クエスト翻訳')),
          body: const QuestTranslationTabView(),
        ),
      );
    }
    return ChangeNotifierProvider<QuestTranslationController>(
      create: (context) => QuestTranslationController(
        settingsController: context.read<SettingsController>(),
      ),
      child: Scaffold(
        appBar: AppBar(title: const Text('クエスト翻訳')),
        body: const QuestTranslationTabView(),
      ),
    );
  }
}

/// クエストタブの中身(4タブ統合シェル([MainShellPage])のタブ本体としても使う)。
///
/// 独自の `Scaffold`/`AppBar` は持たない。
class QuestTranslationTabView extends StatefulWidget {
  const QuestTranslationTabView({super.key});

  @override
  State<QuestTranslationTabView> createState() =>
      QuestTranslationTabViewState();
}

class QuestTranslationTabViewState extends State<QuestTranslationTabView> {
  final _directoryController = TextEditingController();
  late final QuestTranslationController _controller;
  QuestTranslateAndWriteResult? _lastShownResult;

  @override
  void initState() {
    super.initState();
    _controller = context.read<QuestTranslationController>();
    _controller.addListener(_onControllerChanged);
  }

  void _onControllerChanged() {
    if (!mounted) return;
    final result = _controller.lastResult;
    if (_controller.state == QuestTabState.completed &&
        result != null &&
        !identical(result, _lastShownResult)) {
      _lastShownResult = result;
      TranslationCompletionDialog.show(
        context,
        summary: result.summary,
        onShowLog: () => LogViewerDialog.show(
          context,
          logger: _controller.sessionLogger,
          isBusy: false,
        ),
      );
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerChanged);
    _directoryController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<QuestTranslationController>();
    final settings = context.watch<SettingsController>().settings;

    final canScan =
        controller.profileDirectory != null &&
        controller.state != QuestTabState.scanning &&
        controller.state != QuestTabState.translating;
    final canTranslate =
        controller.state == QuestTabState.scanned &&
        controller.selectedPaths.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ProfileDirectoryRow(directoryController: _directoryController),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  key: const Key('targetLanguageSelector'),
                  initialValue: controller.targetLanguageId,
                  decoration: const InputDecoration(labelText: '対象言語'),
                  items: settings.translation.allLanguages
                      .map(
                        (l) => DropdownMenuItem(
                          value: l.id,
                          child: Text(l.displayName),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value != null) controller.setTargetLanguageId(value);
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  key: const Key('searchField'),
                  decoration: const InputDecoration(labelText: '検索(パスの部分一致)'),
                  onChanged: controller.setSearchQuery,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              ElevatedButton(
                key: const Key('scanButton'),
                onPressed: canScan ? controller.scan : null,
                child: const Text('スキャン'),
              ),
              const SizedBox(width: 12),
              ElevatedButton(
                key: const Key('translateButton'),
                onPressed: canTranslate ? controller.translate : null,
                child: const Text('翻訳'),
              ),
              const SizedBox(width: 16),
              Text(
                _stateLabel(controller.state),
                key: const Key('questTabStateLabel'),
              ),
            ],
          ),
          if (controller.state == QuestTabState.translating) ...[
            const SizedBox(height: 12),
            TranslationProgressPanel(
              overallProgress: controller.overallProgress,
              singleFileProgress: controller.singleFileProgress,
              currentItemName: controller.currentItemName,
            ),
          ],
          if (controller.errorMessage != null) ...[
            const SizedBox(height: 8),
            Text(
              controller.errorMessage!,
              key: const Key('questTabErrorMessage'),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          if (controller.lastResult != null) ...[
            const SizedBox(height: 8),
            _ResultSummary(result: controller.lastResult!),
          ],
          const SizedBox(height: 16),
          Expanded(child: _QuestTable(controller: controller)),
        ],
      ),
    );
  }

  String _stateLabel(QuestTabState state) {
    switch (state) {
      case QuestTabState.notSelected:
        return '未選択';
      case QuestTabState.scanning:
        return 'スキャン中...';
      case QuestTabState.scanned:
        return 'スキャン完了';
      case QuestTabState.translating:
        return '翻訳中...';
      case QuestTabState.completed:
        return '完了';
    }
  }
}

class _ProfileDirectoryRow extends StatelessWidget {
  const _ProfileDirectoryRow({required this.directoryController});

  final TextEditingController directoryController;

  @override
  Widget build(BuildContext context) {
    final controller = context.read<QuestTranslationController>();

    return Row(
      children: [
        Expanded(
          child: TextField(
            key: const Key('profileDirectoryField'),
            controller: directoryController,
            decoration: const InputDecoration(labelText: 'プロファイルディレクトリ'),
            onSubmitted: controller.setProfileDirectoryPath,
          ),
        ),
        const SizedBox(width: 12),
        OutlinedButton(
          key: const Key('browseDirectoryButton'),
          onPressed: () async {
            final path = await getDirectoryPath();
            if (path != null) {
              directoryController.text = path;
              controller.setProfileDirectoryPath(path);
            }
          },
          child: const Text('参照'),
        ),
      ],
    );
  }
}

class _ResultSummary extends StatelessWidget {
  const _ResultSummary({required this.result});

  final QuestTranslateAndWriteResult result;

  @override
  Widget build(BuildContext context) {
    final r = result.translationResult;

    return Text(
      '翻訳: ${r.translatedPaths.length} 件 / スキップ: ${r.skippedPaths.length} 件 / '
      '出力ファイル数: ${result.writtenFiles.length}',
      key: const Key('translationResultSummary'),
    );
  }
}

class _QuestTable extends StatelessWidget {
  const _QuestTable({required this.controller});

  final QuestTranslationController controller;

  static const _sortableColumns = [
    QuestTableSortColumn.path,
    QuestTableSortColumn.format,
  ];

  @override
  Widget build(BuildContext context) {
    final entries = controller.visibleEntries;

    return SingleChildScrollView(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          key: const Key('questTable'),
          sortColumnIndex: _sortableColumns.indexOf(controller.sortColumn),
          sortAscending: controller.sortAscending,
          columns: [
            DataColumn(
              label: const Text('パス'),
              onSort: (_, _) =>
                  controller.setSortColumn(QuestTableSortColumn.path),
            ),
            DataColumn(
              label: const Text('形式'),
              onSort: (_, _) =>
                  controller.setSortColumn(QuestTableSortColumn.format),
            ),
          ],
          rows: entries.map((entry) {
            final selected = controller.selectedPaths.contains(
              entry.relativePath,
            );
            return DataRow(
              key: ValueKey('questRow_${entry.relativePath}'),
              selected: selected,
              onSelectChanged: (value) => controller.toggleQuestSelection(
                entry.relativePath,
                value ?? false,
              ),
              cells: [
                DataCell(
                  KeyedSubtree(
                    key: ValueKey('questRow_${entry.relativePath}'),
                    child: Text(entry.relativePath),
                  ),
                ),
                DataCell(Text(_formatLabel(entry.format))),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }

  String _formatLabel(QuestFormat format) {
    switch (format) {
      case QuestFormat.ftbQuestsKubejsLang:
        return 'FTB Quests (KubeJS)';
      case QuestFormat.ftbQuestsSnbt:
        return 'FTB Quests (SNBT)';
      case QuestFormat.betterQuestingStandard:
        return 'Better Quests (標準)';
      case QuestFormat.betterQuestingDirect:
        return 'Better Quests (直接)';
    }
  }
}
