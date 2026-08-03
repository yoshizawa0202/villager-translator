import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../domain/modtranslation/lang_codec.dart';
import '../../infrastructure/modtranslation/mod_translation_orchestrator.dart';
import '../settings/settings_controller.dart';
import 'mod_translation_controller.dart';

/// MOD タブ画面(feature-spec.md §3.1〜3.2、§6)。
///
/// プロファイルディレクトリ選択・スキャン・対象言語選択・テーブル
/// (チェックボックス・ソート・部分一致検索)・翻訳実行を提供する。
class ModTranslationPage extends StatelessWidget {
  const ModTranslationPage({super.key, this.controller});

  /// テスト用にコントローラーを直接注入するためのフック。
  /// 通常利用時は `null` のままで、画面が自前で生成する。
  final ModTranslationController? controller;

  @override
  Widget build(BuildContext context) {
    if (controller != null) {
      return ChangeNotifierProvider<ModTranslationController>.value(
        value: controller!,
        child: const _ModTranslationView(),
      );
    }
    return ChangeNotifierProvider<ModTranslationController>(
      create: (context) => ModTranslationController(
        settingsController: context.read<SettingsController>(),
      ),
      child: const _ModTranslationView(),
    );
  }
}

class _ModTranslationView extends StatefulWidget {
  const _ModTranslationView();

  @override
  State<_ModTranslationView> createState() => _ModTranslationViewState();
}

class _ModTranslationViewState extends State<_ModTranslationView> {
  final _directoryController = TextEditingController();

  @override
  void dispose() {
    _directoryController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<ModTranslationController>();
    final settings = context.watch<SettingsController>().settings;

    final canScan =
        controller.profileDirectory != null &&
        controller.state != ModTabState.scanning &&
        controller.state != ModTabState.translating;
    final canTranslate =
        controller.state == ModTabState.scanned &&
        controller.selectedModIds.isNotEmpty;

    return Scaffold(
      appBar: AppBar(title: const Text('MOD 翻訳')),
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
                      labelText: '検索(MOD 名・ID の部分一致)',
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
                  key: const Key('modTabStateLabel'),
                ),
              ],
            ),
            if (controller.errorMessage != null) ...[
              const SizedBox(height: 8),
              Text(
                controller.errorMessage!,
                key: const Key('modTabErrorMessage'),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            if (controller.lastResult != null) ...[
              const SizedBox(height: 8),
              _ResultSummary(result: controller.lastResult!),
            ],
            const SizedBox(height: 16),
            Expanded(child: _ModTable(controller: controller)),
          ],
        ),
      ),
    );
  }

  String _stateLabel(ModTabState state) {
    switch (state) {
      case ModTabState.notSelected:
        return '未選択';
      case ModTabState.scanning:
        return 'スキャン中...';
      case ModTabState.scanned:
        return 'スキャン完了';
      case ModTabState.translating:
        return '翻訳中...';
      case ModTabState.completed:
        return '完了';
    }
  }
}

class _ProfileDirectoryRow extends StatelessWidget {
  const _ProfileDirectoryRow({required this.directoryController});

  final TextEditingController directoryController;

  @override
  Widget build(BuildContext context) {
    final controller = context.read<ModTranslationController>();

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

  final ModTranslateAndPackResult result;

  @override
  Widget build(BuildContext context) {
    final r = result.translationResult;
    final outputText = result.packDirectory != null
        ? '出力先: ${result.packDirectory!.path}'
        : 'リソースパックは作成されませんでした(全対象がスキップ)';

    return Text(
      '翻訳: ${r.translatedModIds.length} 件 / スキップ: ${r.skippedModIds.length} 件 / $outputText',
      key: const Key('translationResultSummary'),
    );
  }
}

class _ModTable extends StatelessWidget {
  const _ModTable({required this.controller});

  final ModTranslationController controller;

  static const _sortableColumns = [
    ModTableSortColumn.name,
    ModTableSortColumn.id,
    ModTableSortColumn.path,
    ModTableSortColumn.format,
  ];

  @override
  Widget build(BuildContext context) {
    final entries = controller.visibleEntries;

    return SingleChildScrollView(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          key: const Key('modTable'),
          sortColumnIndex: _sortableColumns.indexOf(controller.sortColumn),
          sortAscending: controller.sortAscending,
          columns: [
            DataColumn(
              label: const Text('MOD 名'),
              onSort: (_, _) =>
                  controller.setSortColumn(ModTableSortColumn.name),
            ),
            DataColumn(
              label: const Text('MOD ID'),
              onSort: (_, _) => controller.setSortColumn(ModTableSortColumn.id),
            ),
            DataColumn(
              label: const Text('パス'),
              onSort: (_, _) =>
                  controller.setSortColumn(ModTableSortColumn.path),
            ),
            DataColumn(
              label: const Text('形式'),
              onSort: (_, _) =>
                  controller.setSortColumn(ModTableSortColumn.format),
            ),
            const DataColumn(label: Text('既存翻訳')),
          ],
          rows: entries.map((entry) {
            final selected = controller.selectedModIds.contains(
              entry.modInfo.id,
            );
            return DataRow(
              key: ValueKey('modRow_${entry.modInfo.id}'),
              selected: selected,
              onSelectChanged: (value) => controller.toggleModSelection(
                entry.modInfo.id,
                value ?? false,
              ),
              cells: [
                DataCell(
                  KeyedSubtree(
                    key: ValueKey('modRow_${entry.modInfo.id}'),
                    child: Text(entry.modInfo.name),
                  ),
                ),
                DataCell(Text(entry.modInfo.id)),
                DataCell(Text(entry.jarRelativePath)),
                DataCell(
                  Text(entry.langFormat == LangFormat.json ? 'JSON' : 'LANG'),
                ),
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
