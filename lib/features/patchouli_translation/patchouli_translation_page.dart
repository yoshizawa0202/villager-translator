import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../infrastructure/patchoulitranslation/patchouli_translation_orchestrator.dart';
import '../settings/settings_controller.dart';
import 'patchouli_translation_controller.dart';

/// Patchouli ガイドブック翻訳タブ画面(feature-spec.md §8)。
///
/// プロファイルディレクトリ選択・スキャン・対象言語選択・テーブル
/// (チェックボックス・ソート・部分一致検索)・翻訳実行を提供する。
class PatchouliTranslationPage extends StatelessWidget {
  const PatchouliTranslationPage({super.key, this.controller});

  /// テスト用にコントローラーを直接注入するためのフック。
  /// 通常利用時は `null` のままで、画面が自前で生成する。
  final PatchouliTranslationController? controller;

  @override
  Widget build(BuildContext context) {
    if (controller != null) {
      return ChangeNotifierProvider<PatchouliTranslationController>.value(
        value: controller!,
        child: const _PatchouliTranslationView(),
      );
    }
    return ChangeNotifierProvider<PatchouliTranslationController>(
      create: (context) => PatchouliTranslationController(
        settingsController: context.read<SettingsController>(),
      ),
      child: const _PatchouliTranslationView(),
    );
  }
}

class _PatchouliTranslationView extends StatefulWidget {
  const _PatchouliTranslationView();

  @override
  State<_PatchouliTranslationView> createState() =>
      _PatchouliTranslationViewState();
}

class _PatchouliTranslationViewState extends State<_PatchouliTranslationView> {
  final _directoryController = TextEditingController();

  @override
  void dispose() {
    _directoryController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<PatchouliTranslationController>();
    final settings = context.watch<SettingsController>().settings;

    final canScan =
        controller.profileDirectory != null &&
        controller.state != PatchouliTabState.scanning &&
        controller.state != PatchouliTabState.translating;
    final canTranslate =
        controller.state == PatchouliTabState.scanned &&
        controller.selectedBookKeys.isNotEmpty;

    return Scaffold(
      appBar: AppBar(title: const Text('Patchouli ガイドブック翻訳')),
      body: Padding(
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
                    decoration: const InputDecoration(
                      labelText: '検索(本の modId:bookId の部分一致)',
                    ),
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
                  key: const Key('patchouliTabStateLabel'),
                ),
              ],
            ),
            if (controller.errorMessage != null) ...[
              const SizedBox(height: 8),
              Text(
                controller.errorMessage!,
                key: const Key('patchouliTabErrorMessage'),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            if (controller.lastResult != null) ...[
              const SizedBox(height: 8),
              _ResultSummary(result: controller.lastResult!),
            ],
            const SizedBox(height: 16),
            Expanded(child: _PatchouliTable(controller: controller)),
          ],
        ),
      ),
    );
  }

  String _stateLabel(PatchouliTabState state) {
    switch (state) {
      case PatchouliTabState.notSelected:
        return '未選択';
      case PatchouliTabState.scanning:
        return 'スキャン中...';
      case PatchouliTabState.scanned:
        return 'スキャン完了';
      case PatchouliTabState.translating:
        return '翻訳中...';
      case PatchouliTabState.completed:
        return '完了';
    }
  }
}

class _ProfileDirectoryRow extends StatelessWidget {
  const _ProfileDirectoryRow({required this.directoryController});

  final TextEditingController directoryController;

  @override
  Widget build(BuildContext context) {
    final controller = context.read<PatchouliTranslationController>();

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

  final PatchouliTranslateAndWriteResult result;

  @override
  Widget build(BuildContext context) {
    final r = result.translationResult;

    return Text(
      '翻訳: ${r.translatedBookKeys.length} 件 / スキップ: ${r.skippedBookKeys.length} 件 / '
      '更新した JAR 数: ${result.updatedJarRelativePaths.length}',
      key: const Key('translationResultSummary'),
    );
  }
}

class _PatchouliTable extends StatelessWidget {
  const _PatchouliTable({required this.controller});

  final PatchouliTranslationController controller;

  static const _sortableColumns = [
    PatchouliTableSortColumn.book,
    PatchouliTableSortColumn.path,
    PatchouliTableSortColumn.fileCount,
  ];

  @override
  Widget build(BuildContext context) {
    final entries = controller.visibleEntries;

    return SingleChildScrollView(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          key: const Key('patchouliTable'),
          sortColumnIndex: _sortableColumns.indexOf(controller.sortColumn),
          sortAscending: controller.sortAscending,
          columns: [
            DataColumn(
              label: const Text('本(modId:bookId)'),
              onSort: (_, _) =>
                  controller.setSortColumn(PatchouliTableSortColumn.book),
            ),
            DataColumn(
              label: const Text('パス'),
              onSort: (_, _) =>
                  controller.setSortColumn(PatchouliTableSortColumn.path),
            ),
            DataColumn(
              label: const Text('ファイル数'),
              onSort: (_, _) =>
                  controller.setSortColumn(PatchouliTableSortColumn.fileCount),
            ),
            const DataColumn(label: Text('既存翻訳')),
          ],
          rows: entries.map((entry) {
            final selected = controller.selectedBookKeys.contains(
              entry.bookKey,
            );
            return DataRow(
              key: ValueKey('patchouliRow_${entry.bookKey}'),
              selected: selected,
              onSelectChanged: (value) =>
                  controller.toggleBookSelection(entry.bookKey, value ?? false),
              cells: [
                DataCell(
                  KeyedSubtree(
                    key: ValueKey('patchouliRow_${entry.bookKey}'),
                    child: Text(entry.bookKey),
                  ),
                ),
                DataCell(Text(entry.jarRelativePath)),
                DataCell(Text('${entry.files.length}')),
                DataCell(
                  Chip(label: Text(entry.hasExistingTranslation ? '既存' : '新規')),
                ),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }
}
