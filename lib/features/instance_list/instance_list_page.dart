import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../domain/minecraftinstance/minecraft_instance.dart';
import '../../domain/minecraftinstance/minecraft_launcher.dart';
import '../../domain/settings/app_settings.dart';
import '../../infrastructure/minecraftinstance/instance_store.dart';
import '../../infrastructure/minecraftinstance/windows_environment.dart';
import '../instance_detail/instance_detail_page.dart';
import '../settings/settings_controller.dart';
import '../settings/settings_page.dart';
import '../shell/main_shell_page.dart';
import 'instance_list_controller.dart';
import 'widgets/manual_instance_dialog.dart';

/// Minecraft インスタンス一覧画面(起動時ホーム画面)
/// (011-launcher-instance-discovery.md §13〜§15)。
///
/// 「翻訳する」を押すと、そのインスタンスの解析結果画面([InstanceDetailPage])
/// へ遷移する。従来どおりプロファイルフォルダを手動指定して 4 タブ画面を使う
/// 導線も残す(§17)。
class InstanceListPage extends StatefulWidget {
  const InstanceListPage({
    super.key,
    this.controller,
    this.applicationSupportDirectory,
    this.environment = const PlatformWindowsEnvironment(),
  });

  /// テスト用にコントローラーを直接注入するためのフック。
  final InstanceListController? controller;

  /// `instances.json` の保存先(プロファイル非依存、§15.5)。
  final Directory? applicationSupportDirectory;

  final WindowsEnvironment environment;

  @override
  State<InstanceListPage> createState() => _InstanceListPageState();
}

class _InstanceListPageState extends State<InstanceListPage> {
  late final InstanceListController _controller;
  late final bool _ownsController;

  @override
  void initState() {
    super.initState();
    _ownsController = widget.controller == null;
    final supportDirectory = widget.applicationSupportDirectory;
    _controller =
        widget.controller ??
        InstanceListController(
          environment: widget.environment,
          store: supportDirectory == null
              ? null
              : InstanceStore.forApplicationSupportDirectory(supportDirectory),
        );
    if (_ownsController) {
      _controller.loadAndDiscover();
    }
  }

  @override
  void dispose() {
    if (_ownsController) _controller.dispose();
    super.dispose();
  }

  Future<void> _openInstance(MinecraftInstance instance) async {
    await _controller.markInstanceUsed(instance);
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => InstanceDetailPage(
          instance: instance,
          applicationSupportDirectory: widget.applicationSupportDirectory,
        ),
      ),
    );
  }

  Future<void> _addManualInstance() async {
    final path = await ManualInstanceDialog.show(context);
    if (path == null || !mounted) return;

    final error = await _controller.addManualPath(path);
    if (!mounted || error == null) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<InstanceListController>.value(
      value: _controller,
      child: Consumer<InstanceListController>(
        builder: (context, controller, _) {
          return Scaffold(
            appBar: AppBar(
              title: const Text('Minecraft インスタンス'),
              actions: [
                IconButton(
                  key: const Key('rediscoverButton'),
                  icon: const Icon(Icons.refresh),
                  tooltip: '再検出',
                  onPressed: controller.state == InstanceListState.discovering
                      ? null
                      : controller.discover,
                ),
                IconButton(
                  key: const Key('addManualInstanceButton'),
                  icon: const Icon(Icons.create_new_folder_outlined),
                  tooltip: 'インスタンスを手動追加',
                  onPressed: _addManualInstance,
                ),
                IconButton(
                  key: const Key('openManualProfileButton'),
                  icon: const Icon(Icons.tune),
                  tooltip: 'フォルダを指定して従来の画面を開く',
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => MainShellPage(
                        applicationSupportDirectory:
                            widget.applicationSupportDirectory,
                      ),
                    ),
                  ),
                ),
                Consumer<SettingsController>(
                  builder: (context, settingsController, _) {
                    final isDark =
                        settingsController.settings.themeMode ==
                        AppThemeMode.dark;
                    return IconButton(
                      key: const Key('instanceListThemeToggleButton'),
                      icon: Icon(isDark ? Icons.light_mode : Icons.dark_mode),
                      tooltip: 'テーマ切替',
                      onPressed: () => settingsController.setThemeMode(
                        isDark ? AppThemeMode.light : AppThemeMode.dark,
                      ),
                    );
                  },
                ),
                IconButton(
                  key: const Key('instanceListSettingsButton'),
                  icon: const Icon(Icons.settings),
                  tooltip: '設定',
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const SettingsPage(),
                    ),
                  ),
                ),
              ],
            ),
            body: _InstanceListBody(onOpenInstance: _openInstance),
          );
        },
      ),
    );
  }
}

/// 一覧本体(フィルター・検索・最近使用・ランチャー別の一覧・詳細検索)。
class _InstanceListBody extends StatelessWidget {
  const _InstanceListBody({required this.onOpenInstance});

  final Future<void> Function(MinecraftInstance instance) onOpenInstance;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<InstanceListController>();

    if (controller.state == InstanceListState.discovering) {
      return const Center(
        key: Key('instanceDiscoveryProgress'),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 12),
            Text('Minecraft インスタンスを検出しています...'),
          ],
        ),
      );
    }

    if (controller.state == InstanceListState.deepSearching) {
      return _DeepSearchProgress(controller: controller);
    }

    return ListView(
      key: const Key('instanceList'),
      padding: const EdgeInsets.all(16),
      children: [
        const _FilterRow(),
        if (controller.errorMessage != null) ...[
          const SizedBox(height: 12),
          Text(
            controller.errorMessage!,
            key: const Key('instanceListErrorMessage'),
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
        if (controller.recentInstances.isNotEmpty) ...[
          const SizedBox(height: 16),
          _RecentInstanceSection(onOpenInstance: onOpenInstance),
        ],
        const SizedBox(height: 16),
        if (controller.visibleInstances.isEmpty)
          _EmptyState(controller: controller)
        else
          for (final entry in controller.visibleByLauncher.entries) ...[
            _LauncherHeading(launcher: entry.key),
            for (final instance in entry.value)
              _InstanceCard(
                instance: instance,
                modJarCount: controller.modJarCountOf(instance),
                onOpen: () => onOpenInstance(instance),
              ),
            const SizedBox(height: 16),
          ],
      ],
    );
  }
}

/// ランチャー別フィルターとインスタンス名検索(§14)。
class _FilterRow extends StatelessWidget {
  const _FilterRow();

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<InstanceListController>();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          key: const Key('instanceSearchField'),
          decoration: const InputDecoration(
            labelText: 'インスタンス名で検索',
            prefixIcon: Icon(Icons.search),
          ),
          onChanged: controller.setSearchQuery,
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          children: [
            FilterChip(
              key: const Key('launcherFilterAll'),
              label: const Text('すべて'),
              selected: controller.launcherFilter == null,
              onSelected: (_) => controller.setLauncherFilter(null),
            ),
            for (final launcher in MinecraftLauncher.values)
              FilterChip(
                key: Key('launcherFilter_${launcher.name}'),
                label: Text(launcher.filterLabel),
                selected: controller.launcherFilter == launcher,
                onSelected: (_) => controller.setLauncherFilter(launcher),
              ),
          ],
        ),
      ],
    );
  }
}

class _LauncherHeading extends StatelessWidget {
  const _LauncherHeading({required this.launcher});

  final MinecraftLauncher launcher;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        launcher.displayName,
        key: Key('launcherHeading_${launcher.name}'),
        style: Theme.of(context).textTheme.titleMedium,
      ),
    );
  }
}

/// インスタンス 1 件分のカード(名前・Minecraft バージョン・Mod Loader・
/// MOD 件数・「翻訳する」、§13)。
class _InstanceCard extends StatelessWidget {
  const _InstanceCard({
    required this.instance,
    required this.modJarCount,
    required this.onOpen,
  });

  final MinecraftInstance instance;
  final int modJarCount;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return Card(
      key: Key('instanceCard_${instance.id}'),
      child: ListTile(
        title: Text(instance.name),
        subtitle: Text(
          'Minecraft ${instance.minecraftVersionLabel} / '
          '${instance.modLoader.displayName} / MOD $modJarCount 個\n'
          '${instance.rootPath}',
        ),
        isThreeLine: true,
        trailing: FilledButton(
          key: Key('translateInstanceButton_${instance.id}'),
          onPressed: onOpen,
          child: const Text('翻訳する'),
        ),
      ),
    );
  }
}

/// 最近使用したインスタンス(一覧上部、§15.4)。
class _RecentInstanceSection extends StatelessWidget {
  const _RecentInstanceSection({required this.onOpenInstance});

  final Future<void> Function(MinecraftInstance instance) onOpenInstance;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<InstanceListController>();

    return Column(
      key: const Key('recentInstanceSection'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('最近使用', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        for (final recent in controller.recentInstances)
          Card(
            key: Key('recentInstanceCard_${recent.id}'),
            child: ListTile(
              title: Text(recent.name),
              subtitle: Text(
                controller.isRecentMissing(recent)
                    ? '見つかりません(${recent.rootPath})'
                    : '${recent.launcher.displayName} / ${recent.rootPath}',
              ),
              trailing: controller.isRecentMissing(recent)
                  ? IconButton(
                      key: Key('removeRecentInstanceButton_${recent.id}'),
                      icon: const Icon(Icons.delete_outline),
                      tooltip: '一覧から削除',
                      onPressed: () =>
                          controller.removeRecentInstance(recent.id),
                    )
                  : OutlinedButton(
                      key: Key('openRecentInstanceButton_${recent.id}'),
                      onPressed: () {
                        final instance = controller.resolveRecent(recent);
                        if (instance != null) onOpenInstance(instance);
                      },
                      child: const Text('開く'),
                    ),
            ),
          ),
      ],
    );
  }
}

/// 検出結果が 0 件のときの表示(§15.3: 自動検出が 0 件の場合にのみ詳細検索を提示)。
class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.controller});

  final InstanceListController controller;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const Key('instanceListEmptyState'),
      children: [
        const Text('Minecraft インスタンスが見つかりませんでした。'),
        const SizedBox(height: 8),
        const Text('インスタンスが見つかりませんか?'),
        const SizedBox(height: 8),
        if (controller.canOfferDeepSearch)
          OutlinedButton.icon(
            key: const Key('deepSearchButton'),
            onPressed: controller.deepSearch,
            icon: const Icon(Icons.travel_explore),
            label: const Text('PC内を詳しく検索'),
          ),
      ],
    );
  }
}

/// 詳細検索の進捗(探索中のパス表示とキャンセル、§15.3)。
class _DeepSearchProgress extends StatelessWidget {
  const _DeepSearchProgress({required this.controller});

  final InstanceListController controller;

  @override
  Widget build(BuildContext context) {
    return Padding(
      key: const Key('deepSearchProgress'),
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const LinearProgressIndicator(),
          const SizedBox(height: 12),
          Text(
            controller.deepSearchCurrentPath ?? 'PC 内を検索しています...',
            key: const Key('deepSearchCurrentPath'),
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            key: const Key('cancelDeepSearchButton'),
            onPressed: controller.isDeepSearchCancelling
                ? null
                : controller.cancelDeepSearch,
            child: Text(
              controller.isDeepSearchCancelling ? 'キャンセル中...' : 'キャンセル',
            ),
          ),
        ],
      ),
    );
  }
}
