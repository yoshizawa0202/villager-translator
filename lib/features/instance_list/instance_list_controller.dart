import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../domain/common/cancellation_token.dart';
import '../../domain/minecraftinstance/instance_deduplicator.dart';
import '../../domain/minecraftinstance/instance_validator.dart';
import '../../domain/minecraftinstance/minecraft_instance.dart';
import '../../domain/minecraftinstance/minecraft_launcher.dart';
import '../../domain/minecraftinstance/recent_instance.dart';
import '../../infrastructure/minecraftinstance/deep_instance_search.dart';
import '../../infrastructure/minecraftinstance/instance_store.dart';
import '../../infrastructure/minecraftinstance/launcher_detector.dart';
import '../../infrastructure/minecraftinstance/launcher_discovery_service.dart';
import '../../infrastructure/minecraftinstance/mod_jar_counter.dart';
import '../../infrastructure/minecraftinstance/windows_environment.dart';

/// 詳細検索の実行関数(テストで差し替えるための注入点、§15.3)。
typedef DeepInstanceSearch =
    Future<List<MinecraftInstance>> Function({
      required WindowsEnvironment environment,
      CancellationToken? cancellationToken,
      void Function(String path)? onDirectoryVisited,
    });

/// インスタンス一覧画面の状態遷移
/// (011-launcher-instance-discovery.md §13、§15)。
enum InstanceListState { idle, discovering, discovered, deepSearching }

/// インスタンス一覧画面の状態を保持し、検出・フィルター・手動追加・詳細検索・
/// 最近使用の管理を統括する(§13〜§15)。
class InstanceListController extends ChangeNotifier {
  InstanceListController({
    required WindowsEnvironment environment,
    InstanceStore? store,
    LauncherDiscoveryService Function(List<String> manualPaths)?
    discoveryServiceFactory,
    DeepInstanceSearch? deepSearch,
  }) : _environment = environment,
       _store = store,
       _discoveryServiceFactory =
           discoveryServiceFactory ??
           ((manualPaths) => LauncherDiscoveryService(
             environment: environment,
             manualPaths: manualPaths,
           )),
       _deepSearch = deepSearch ?? searchInstancesDeeply;

  final WindowsEnvironment _environment;

  /// `instances.json`(手動追加パス・最近使用)。`null` のときは永続化しない
  /// (アプリケーションサポートディレクトリを解決できないテスト時など)。
  final InstanceStore? _store;

  final LauncherDiscoveryService Function(List<String> manualPaths)
  _discoveryServiceFactory;

  final DeepInstanceSearch _deepSearch;

  InstanceListState _state = InstanceListState.idle;
  InstanceListState get state => _state;

  List<MinecraftInstance> _instances = const [];

  /// 検出済みインスタンス(重複排除・整列済み)。
  List<MinecraftInstance> get instances => List.unmodifiable(_instances);

  /// インスタンス ID → `mods/*.jar` のファイル数(§13)。
  final Map<String, int> _modJarCounts = {};
  int modJarCountOf(MinecraftInstance instance) =>
      _modJarCounts[instance.id] ?? 0;

  List<String> _manualPaths = const [];
  List<String> get manualPaths => List.unmodifiable(_manualPaths);

  List<RecentInstance> _recentInstances = const [];
  List<RecentInstance> get recentInstances =>
      List.unmodifiable(_recentInstances);

  /// 最近使用のうち `rootPath` が現存しないもの(「見つかりません」表示、§15.4)。
  final Set<String> _missingRecentIds = {};
  bool isRecentMissing(RecentInstance recent) =>
      _missingRecentIds.contains(recent.id);

  /// ランチャー別フィルター(`null` は「すべて」、§14)。
  MinecraftLauncher? _launcherFilter;
  MinecraftLauncher? get launcherFilter => _launcherFilter;

  String _searchQuery = '';
  String get searchQuery => _searchQuery;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  /// 詳細検索中に探索しているパス(§15.3)。
  String? _deepSearchCurrentPath;
  String? get deepSearchCurrentPath => _deepSearchCurrentPath;

  CancellationToken? _deepSearchToken;
  bool get isDeepSearchCancelling => _deepSearchToken?.isCancelled ?? false;

  /// 検出が完了し、かつ 1 件も見つからなかったか(§15.3: このときだけ
  /// 「PC内を詳しく検索」を提示する)。
  bool get canOfferDeepSearch =>
      _state == InstanceListState.discovered && _instances.isEmpty;

  /// フィルターと検索を適用した表示用の一覧(§14)。
  ///
  /// 並び順は検出時に確定済み([sortInstancesForDisplay])のため、ここでは
  /// 絞り込みだけを行う。
  List<MinecraftInstance> get visibleInstances {
    final query = _searchQuery.trim().toLowerCase();
    return _instances.where((instance) {
      if (_launcherFilter != null && instance.launcher != _launcherFilter) {
        return false;
      }
      if (query.isEmpty) return true;
      return instance.name.toLowerCase().contains(query);
    }).toList();
  }

  /// 表示用の一覧をランチャーごとにまとめる(§13 の見出し表示)。
  Map<MinecraftLauncher, List<MinecraftInstance>> get visibleByLauncher {
    final grouped = <MinecraftLauncher, List<MinecraftInstance>>{};
    for (final instance in visibleInstances) {
      grouped.putIfAbsent(instance.launcher, () => []).add(instance);
    }
    return grouped;
  }

  void setLauncherFilter(MinecraftLauncher? launcher) {
    _launcherFilter = launcher;
    notifyListeners();
  }

  void setSearchQuery(String query) {
    _searchQuery = query;
    notifyListeners();
  }

  /// 保存済みの手動追加パス・最近使用を読み込み、続けて検出する(§15.2、§15.5)。
  Future<void> loadAndDiscover() async {
    final data = await _store?.load();
    _manualPaths = data?.manualPaths ?? const [];
    _recentInstances = data?.recentInstances ?? const [];
    await _refreshMissingRecents();
    await discover();
  }

  /// 標準パス → ランチャー設定 → 登録済み追加パス の順に検出する(§3、AC-17)。
  Future<void> discover() async {
    _state = InstanceListState.discovering;
    _errorMessage = null;
    notifyListeners();

    final failures = <String>[];
    final discovered = await _discoveryServiceFactory(_manualPaths).discoverAll(
      onDetectorError: (detector, error) =>
          failures.add('${detector.launcher.displayName}: $error'),
    );

    _instances = discovered;
    await _refreshModJarCounts();
    await _refreshMissingRecents();

    // 1つのランチャー設定が壊れていても他ランチャーの検出は継続する(AC-20)。
    // 利用者には「その分だけ検出できなかった」ことを伝える。
    _errorMessage = failures.isEmpty
        ? null
        : '一部のランチャーを検出できませんでした(${failures.join(' / ')})';
    _state = InstanceListState.discovered;
    notifyListeners();
  }

  /// 手動でインスタンス(またはランチャールート)を追加する(§15.1)。
  ///
  /// インスタンス検証もランチャールート判定も満たさないパスは登録せず、
  /// 日本語のエラーメッセージを返す(AC-16)。
  Future<String?> addManualPath(String path) async {
    final trimmed = path.trim();
    if (trimmed.isEmpty) return 'フォルダのパスを入力してください。';

    final directory = Directory(trimmed);
    if (!await directory.exists()) {
      return '指定されたフォルダが見つかりません: $trimmed';
    }

    final childNames = await listDirectChildNames(directory);
    if (!looksLikeMinecraftInstance(childNames) &&
        !looksLikeLauncherRoot(childNames)) {
      return 'Minecraft インスタンスとしても、ランチャーのフォルダとしても認識できませんでした: $trimmed';
    }

    final normalized = await normalizeInstancePath(trimmed);
    if (_manualPaths.any(
      (existing) => existing.toLowerCase() == normalized.toLowerCase(),
    )) {
      return 'このフォルダは既に追加されています: $normalized';
    }

    _manualPaths = [..._manualPaths, normalized];
    await _persist();
    await discover();
    return null;
  }

  Future<void> removeManualPath(String path) async {
    _manualPaths = _manualPaths
        .where((existing) => existing.toLowerCase() != path.toLowerCase())
        .toList();
    await _persist();
    await discover();
  }

  /// PC 内の詳細検索(§15.3)。自動検出が 0 件のときにのみ利用者が実行する。
  Future<void> deepSearch() async {
    final token = CancellationToken();
    _deepSearchToken = token;
    _state = InstanceListState.deepSearching;
    _deepSearchCurrentPath = null;
    _errorMessage = null;
    notifyListeners();

    try {
      final found = await _deepSearch(
        environment: _environment,
        cancellationToken: token,
        onDirectoryVisited: (path) {
          _deepSearchCurrentPath = path;
          notifyListeners();
        },
      );
      _instances = sortInstancesForDisplay(
        deduplicateInstances([..._instances, ...found]),
      );
      await _refreshModJarCounts();
    } catch (e) {
      _errorMessage = 'PC 内の検索に失敗しました: $e';
    } finally {
      _deepSearchToken = null;
      _deepSearchCurrentPath = null;
      _state = InstanceListState.discovered;
    }
    notifyListeners();
  }

  void cancelDeepSearch() {
    _deepSearchToken?.cancel();
    notifyListeners();
  }

  /// 選択したインスタンスを最近使用へ記録する(§15.4)。
  Future<void> markInstanceUsed(
    MinecraftInstance instance, [
    DateTime? now,
  ]) async {
    _recentInstances = pushRecentInstance(
      _recentInstances,
      RecentInstance.fromInstance(instance, now ?? DateTime.now()),
    );
    _missingRecentIds.remove(instance.id);
    await _persist();
    notifyListeners();
  }

  /// 最近使用から 1 件削除する(存在しなくなったインスタンス用、§15.4)。
  Future<void> removeRecentInstance(String id) async {
    _recentInstances = _recentInstances.where((e) => e.id != id).toList();
    _missingRecentIds.remove(id);
    await _persist();
    notifyListeners();
  }

  /// 最近使用から検出済み一覧の同一インスタンスを引き当てる。
  /// 見つからない場合は `null`(再検出前・パスが消えている場合)。
  MinecraftInstance? resolveRecent(RecentInstance recent) {
    for (final instance in _instances) {
      if (instance.id == recent.id) return instance;
      if (instance.rootPath.toLowerCase() == recent.rootPath.toLowerCase()) {
        return instance;
      }
    }
    return null;
  }

  Future<void> _refreshModJarCounts() async {
    _modJarCounts.clear();
    for (final instance in _instances) {
      _modJarCounts[instance.id] = await countModJarFiles(
        Directory(instance.rootPath),
      );
    }
  }

  Future<void> _refreshMissingRecents() async {
    _missingRecentIds.clear();
    for (final recent in _recentInstances) {
      if (!await Directory(recent.rootPath).exists()) {
        _missingRecentIds.add(recent.id);
      }
    }
  }

  Future<void> _persist() async {
    await _store?.save(
      InstanceStoreData(
        manualPaths: _manualPaths,
        recentInstances: _recentInstances,
      ),
    );
  }
}
