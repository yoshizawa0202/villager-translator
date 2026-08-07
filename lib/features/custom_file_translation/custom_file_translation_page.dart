import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../infrastructure/customfiletranslation/custom_file_translation_orchestrator.dart';
import '../settings/settings_controller.dart';
import '../shell/widgets/cancel_confirmation_dialog.dart';
import '../shell/widgets/log_viewer_dialog.dart';
import '../shell/widgets/translation_completion_dialog.dart';
import '../shell/widgets/translation_progress_panel.dart';
import 'custom_file_translation_controller.dart';

/// カスタムファイルタブ画面(feature-spec.md §9)。
///
/// ルートディレクトリ選択・スキャン・対象言語選択・テーブル(チェックボックス・
/// ソート・部分一致検索)・翻訳実行を提供する。
class CustomFileTranslationPage extends StatelessWidget {
  const CustomFileTranslationPage({super.key, this.controller});

  /// テスト用にコントローラーを直接注入するためのフック。
  /// 通常利用時は `null` のままで、画面が自前で生成する。
  final CustomFileTranslationController? controller;

  @override
  Widget build(BuildContext context) {
    if (controller != null) {
      return ChangeNotifierProvider<CustomFileTranslationController>.value(
        value: controller!,
        child: Scaffold(
          appBar: AppBar(title: const Text('カスタムファイル翻訳')),
          body: const CustomFileTranslationTabView(),
        ),
      );
    }
    return ChangeNotifierProvider<CustomFileTranslationController>(
      create: (context) => CustomFileTranslationController(
        settingsController: context.read<SettingsController>(),
      ),
      child: Scaffold(
        appBar: AppBar(title: const Text('カスタムファイル翻訳')),
        body: const CustomFileTranslationTabView(),
      ),
    );
  }
}

/// カスタムファイルタブの中身(4タブ統合シェル([MainShellPage])のタブ本体としても使う)。
///
/// 独自の `Scaffold`/`AppBar` は持たない。
class CustomFileTranslationTabView extends StatefulWidget {
  const CustomFileTranslationTabView({super.key});

  @override
  State<CustomFileTranslationTabView> createState() =>
      CustomFileTranslationTabViewState();
}

class CustomFileTranslationTabViewState
    extends State<CustomFileTranslationTabView> {
  final _directoryController = TextEditingController();
  late final CustomFileTranslationController _controller;
  CustomFileTranslateAndWriteResult? _lastShownResult;

  @override
  void initState() {
    super.initState();
    _controller = context.read<CustomFileTranslationController>();
    _controller.addListener(_onControllerChanged);
  }

  void _onControllerChanged() {
    if (!mounted) return;
    final result = _controller.lastResult;
    if (_controller.state == CustomFileTabState.completed &&
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
    final controller = context.watch<CustomFileTranslationController>();
    final settings = context.watch<SettingsController>().settings;

    final canScan =
        controller.profileDirectory != null &&
        controller.state != CustomFileTabState.scanning &&
        controller.state != CustomFileTabState.translating;
    final canTranslate =
        controller.state == CustomFileTabState.scanned &&
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
                key: const Key('customFileTabStateLabel'),
              ),
            ],
          ),
          if (controller.state == CustomFileTabState.translating) ...[
            const SizedBox(height: 12),
            TranslationProgressPanel(
              overallProgress: controller.overallProgress,
              singleFileProgress: controller.singleFileProgress,
              currentItemName: controller.currentItemName,
              isCancelling: controller.isCancelling,
              onCancel: () async {
                final confirmed = await CancelConfirmationDialog.show(context);
                if (confirmed) controller.cancel();
              },
            ),
          ],
          if (controller.errorMessage != null) ...[
            const SizedBox(height: 8),
            Text(
              controller.errorMessage!,
              key: const Key('customFileTabErrorMessage'),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          if (controller.lastResult != null) ...[
            const SizedBox(height: 8),
            _ResultSummary(result: controller.lastResult!),
          ],
          const SizedBox(height: 16),
          Expanded(child: _CustomFileTable(controller: controller)),
        ],
      ),
    );
  }

  String _stateLabel(CustomFileTabState state) {
    switch (state) {
      case CustomFileTabState.notSelected:
        return '未選択';
      case CustomFileTabState.scanning:
        return 'スキャン中...';
      case CustomFileTabState.scanned:
        return 'スキャン完了';
      case CustomFileTabState.translating:
        return '翻訳中...';
      case CustomFileTabState.completed:
        return '完了';
    }
  }
}

class _ProfileDirectoryRow extends StatelessWidget {
  const _ProfileDirectoryRow({required this.directoryController});

  final TextEditingController directoryController;

  @override
  Widget build(BuildContext context) {
    final controller = context.read<CustomFileTranslationController>();

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

  final CustomFileTranslateAndWriteResult result;

  @override
  Widget build(BuildContext context) {
    final r = result.translationResult;
    final outputText = result.outputDirectory != null
        ? '出力先: ${result.outputDirectory!.path}'
        : '出力ファイルは作成されませんでした(全対象がスキップ)';

    return Text(
      '翻訳: ${r.translatedPaths.length} 件 / スキップ: ${r.skippedPaths.length} 件 / $outputText',
      key: const Key('translationResultSummary'),
    );
  }
}

class _CustomFileTable extends StatelessWidget {
  const _CustomFileTable({required this.controller});

  final CustomFileTranslationController controller;

  static const _sortableColumns = [
    CustomFileTableSortColumn.path,
    CustomFileTableSortColumn.format,
  ];

  @override
  Widget build(BuildContext context) {
    final entries = controller.visibleEntries;

    return SingleChildScrollView(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          key: const Key('customFileTable'),
          sortColumnIndex: _sortableColumns.indexOf(controller.sortColumn),
          sortAscending: controller.sortAscending,
          columns: [
            DataColumn(
              label: const Text('パス'),
              onSort: (_, _) =>
                  controller.setSortColumn(CustomFileTableSortColumn.path),
            ),
            DataColumn(
              label: const Text('形式'),
              onSort: (_, _) =>
                  controller.setSortColumn(CustomFileTableSortColumn.format),
            ),
          ],
          rows: entries.map((entry) {
            final selected = controller.selectedPaths.contains(
              entry.relativePath,
            );
            return DataRow(
              key: ValueKey('customFileRow_${entry.relativePath}'),
              selected: selected,
              onSelectChanged: (value) => controller.toggleFileSelection(
                entry.relativePath,
                value ?? false,
              ),
              cells: [
                DataCell(
                  KeyedSubtree(
                    key: ValueKey('customFileRow_${entry.relativePath}'),
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

  String _formatLabel(CustomFileFormat format) {
    switch (format) {
      case CustomFileFormat.json:
        return 'JSON';
      case CustomFileFormat.snbt:
        return 'SNBT';
    }
  }
}
