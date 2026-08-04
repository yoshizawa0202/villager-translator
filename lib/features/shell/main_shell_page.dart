import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../domain/settings/app_settings.dart';
import '../../infrastructure/common/session_logger.dart';
import '../custom_file_translation/custom_file_translation_controller.dart';
import '../custom_file_translation/custom_file_translation_page.dart';
import '../mod_translation/mod_translation_controller.dart';
import '../mod_translation/mod_translation_page.dart';
import '../patchouli_translation/patchouli_translation_controller.dart';
import '../patchouli_translation/patchouli_translation_page.dart';
import '../quest_translation/quest_translation_controller.dart';
import '../quest_translation/quest_translation_page.dart';
import '../settings/settings_controller.dart';
import '../settings/settings_page.dart';
import 'profile_directory_controller.dart';
import 'widgets/history_dialog.dart';
import 'widgets/log_viewer_dialog.dart';

/// 4タブ(MOD/クエスト/ガイドブック/カスタムファイル)を1画面に統合するシェル
/// (feature-spec.md §3.1、008-progress-log-history.md)。
///
/// プロファイルディレクトリ選択を全タブで共有し([ProfileDirectoryController])、
/// いずれかのタブがスキャン中・翻訳中の間は他タブへの切替を禁止する
/// (受け入れ条件1)。
class MainShellPage extends StatefulWidget {
  const MainShellPage({
    super.key,
    this.profileDirectoryController,
    this.modController,
    this.questController,
    this.patchouliController,
    this.customFileController,
  });

  /// テスト用にコントローラーを直接注入するためのフック群。
  /// 通常利用時は `null` のままで、画面が自前で生成する。
  final ProfileDirectoryController? profileDirectoryController;
  final ModTranslationController? modController;
  final QuestTranslationController? questController;
  final PatchouliTranslationController? patchouliController;
  final CustomFileTranslationController? customFileController;

  @override
  State<MainShellPage> createState() => _MainShellPageState();
}

class _MainShellPageState extends State<MainShellPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  late final ProfileDirectoryController _profileDirectoryController;
  late final ModTranslationController _modController;
  late final QuestTranslationController _questController;
  late final PatchouliTranslationController _patchouliController;
  late final CustomFileTranslationController _customFileController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);

    final settingsController = context.read<SettingsController>();
    _profileDirectoryController =
        widget.profileDirectoryController ?? ProfileDirectoryController();
    _modController =
        widget.modController ??
        ModTranslationController(
          settingsController: settingsController,
          profileDirectoryController: _profileDirectoryController,
        );
    _questController =
        widget.questController ??
        QuestTranslationController(
          settingsController: settingsController,
          profileDirectoryController: _profileDirectoryController,
        );
    _patchouliController =
        widget.patchouliController ??
        PatchouliTranslationController(
          settingsController: settingsController,
          profileDirectoryController: _profileDirectoryController,
        );
    _customFileController =
        widget.customFileController ??
        CustomFileTranslationController(
          settingsController: settingsController,
          profileDirectoryController: _profileDirectoryController,
        );
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  bool _isBusy(Enum state) =>
      state.name == 'scanning' || state.name == 'translating';

  SessionLogger _currentTabSessionLogger() {
    switch (_tabController.index) {
      case 0:
        return _modController.sessionLogger;
      case 1:
        return _questController.sessionLogger;
      case 2:
        return _patchouliController.sessionLogger;
      default:
        return _customFileController.sessionLogger;
    }
  }

  bool _currentTabIsBusy() {
    switch (_tabController.index) {
      case 0:
        return _isBusy(_modController.state);
      case 1:
        return _isBusy(_questController.state);
      case 2:
        return _isBusy(_patchouliController.state);
      default:
        return _isBusy(_customFileController.state);
    }
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<ProfileDirectoryController>.value(
          value: _profileDirectoryController,
        ),
        ChangeNotifierProvider<ModTranslationController>.value(
          value: _modController,
        ),
        ChangeNotifierProvider<QuestTranslationController>.value(
          value: _questController,
        ),
        ChangeNotifierProvider<PatchouliTranslationController>.value(
          value: _patchouliController,
        ),
        ChangeNotifierProvider<CustomFileTranslationController>.value(
          value: _customFileController,
        ),
      ],
      child: AnimatedBuilder(
        animation: Listenable.merge([
          _modController,
          _questController,
          _patchouliController,
          _customFileController,
        ]),
        builder: (context, _) {
          final isBusy =
              _isBusy(_modController.state) ||
              _isBusy(_questController.state) ||
              _isBusy(_patchouliController.state) ||
              _isBusy(_customFileController.state);

          return Scaffold(
            appBar: AppBar(
              title: const Text('Villager Translator'),
              bottom: PreferredSize(
                preferredSize: const Size.fromHeight(48),
                child: IgnorePointer(
                  ignoring: isBusy,
                  child: Opacity(
                    opacity: isBusy ? 0.5 : 1,
                    child: TabBar(
                      key: const Key('mainShellTabBar'),
                      controller: _tabController,
                      tabs: const [
                        Tab(text: 'MOD', key: Key('modTab')),
                        Tab(text: 'クエスト', key: Key('questTab')),
                        Tab(text: 'ガイドブック', key: Key('patchouliTab')),
                        Tab(text: 'カスタムファイル', key: Key('customFileTab')),
                      ],
                    ),
                  ),
                ),
              ),
              actions: [
                IconButton(
                  key: const Key('openLogViewerButton'),
                  icon: const Icon(Icons.article_outlined),
                  tooltip: 'ログ',
                  onPressed: () => LogViewerDialog.show(
                    context,
                    logger: _currentTabSessionLogger(),
                    isBusy: _currentTabIsBusy(),
                  ),
                ),
                IconButton(
                  key: const Key('openHistoryButton'),
                  icon: const Icon(Icons.history),
                  tooltip: '翻訳履歴',
                  onPressed: () => HistoryDialog.show(
                    context,
                    initialDirectory:
                        _profileDirectoryController.profileDirectory,
                  ),
                ),
                Consumer<SettingsController>(
                  builder: (context, settingsController, _) {
                    final isDark =
                        settingsController.settings.themeMode ==
                        AppThemeMode.dark;
                    return IconButton(
                      key: const Key('themeToggleButton'),
                      icon: Icon(isDark ? Icons.light_mode : Icons.dark_mode),
                      tooltip: 'テーマ切替',
                      onPressed: () => settingsController.setThemeMode(
                        isDark ? AppThemeMode.light : AppThemeMode.dark,
                      ),
                    );
                  },
                ),
                IconButton(
                  key: const Key('openSettingsButton'),
                  icon: const Icon(Icons.settings),
                  tooltip: '設定',
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (context) =>
                            SettingsPage(isTranslationRunning: isBusy),
                      ),
                    );
                  },
                ),
              ],
            ),
            body: TabBarView(
              key: const Key('mainShellTabBarView'),
              controller: _tabController,
              physics: isBusy ? const NeverScrollableScrollPhysics() : null,
              children: const [
                ModTranslationTabView(),
                QuestTranslationTabView(),
                PatchouliTranslationTabView(),
                CustomFileTranslationTabView(),
              ],
            ),
          );
        },
      ),
    );
  }
}
