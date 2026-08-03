import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../domain/settings/supported_language.dart';
import '../../infrastructure/modtranslation/mod_translation_orchestrator.dart';
import '../settings/settings_controller.dart';

/// MOD タブの状態遷移(feature-spec.md §3.1〜3.2、本仕様(004)の対象範囲)。
///
/// 未選択→スキャン中→スキャン完了→翻訳中→完了、の単一タブ内の遷移のみを扱う
/// (他タブとの排他制御は `008` で統合する)。
enum ModTabState { notSelected, scanning, scanned, translating, completed }

/// テーブルのソート対象列。
enum ModTableSortColumn { name, id, path, format }

String _defaultSessionId() =>
    DateTime.now().toIso8601String().replaceAll(RegExp(r'[:.]'), '-');

/// MOD タブの状態を保持し、スキャン・選択・翻訳を統括する
/// (feature-spec.md §3.1〜3.2、§6)。
class ModTranslationController extends ChangeNotifier {
  ModTranslationController({
    required SettingsController settingsController,
    ModTranslationOrchestrator? orchestrator,
    String Function()? sessionIdGenerator,
  }) : _settingsController = settingsController,
       _orchestrator = orchestrator ?? ModTranslationOrchestrator(),
       _sessionIdGenerator = sessionIdGenerator ?? _defaultSessionId;

  final SettingsController _settingsController;
  final ModTranslationOrchestrator _orchestrator;
  final String Function() _sessionIdGenerator;

  ModTabState _state = ModTabState.notSelected;
  ModTabState get state => _state;

  Directory? _profileDirectory;
  Directory? get profileDirectory => _profileDirectory;

  ModScanResult? _scanResult;
  ModScanResult? get scanResult => _scanResult;

  final Set<String> _selectedModIds = {};
  Set<String> get selectedModIds => Set.unmodifiable(_selectedModIds);

  /// MOD タブ専用の対象言語選択状態(feature-spec.md §3.1、対象外セクション参照)。
  String _targetLanguageId = kDefaultLanguages.first.id;
  String get targetLanguageId => _targetLanguageId;

  String _searchQuery = '';
  String get searchQuery => _searchQuery;

  ModTableSortColumn _sortColumn = ModTableSortColumn.name;
  ModTableSortColumn get sortColumn => _sortColumn;

  bool _sortAscending = true;
  bool get sortAscending => _sortAscending;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  ModTranslateAndPackResult? _lastResult;
  ModTranslateAndPackResult? get lastResult => _lastResult;

  /// 検索・ソートを適用したテーブル表示用の一覧。
  List<ModScanEntry> get visibleEntries {
    final entries = _scanResult?.entries ?? const <ModScanEntry>[];
    final query = _searchQuery.trim().toLowerCase();
    final filtered = query.isEmpty
        ? entries.toList()
        : entries
              .where(
                (e) =>
                    e.modInfo.name.toLowerCase().contains(query) ||
                    e.modInfo.id.toLowerCase().contains(query),
              )
              .toList();

    int compare(ModScanEntry a, ModScanEntry b) {
      switch (_sortColumn) {
        case ModTableSortColumn.name:
          return a.modInfo.name.compareTo(b.modInfo.name);
        case ModTableSortColumn.id:
          return a.modInfo.id.compareTo(b.modInfo.id);
        case ModTableSortColumn.path:
          return a.jarRelativePath.compareTo(b.jarRelativePath);
        case ModTableSortColumn.format:
          return a.langFormat.name.compareTo(b.langFormat.name);
      }
    }

    filtered.sort(_sortAscending ? compare : (a, b) => compare(b, a));
    return filtered;
  }

  /// プロファイルディレクトリを設定する。以前のスキャン結果・選択状態は破棄する。
  void setProfileDirectoryPath(String path) {
    _profileDirectory = Directory(path);
    _scanResult = null;
    _selectedModIds.clear();
    _errorMessage = null;
    _state = ModTabState.notSelected;
    notifyListeners();
  }

  void setTargetLanguageId(String languageId) {
    _targetLanguageId = languageId;
    notifyListeners();
  }

  void setSearchQuery(String query) {
    _searchQuery = query;
    notifyListeners();
  }

  void setSortColumn(ModTableSortColumn column) {
    if (_sortColumn == column) {
      _sortAscending = !_sortAscending;
    } else {
      _sortColumn = column;
      _sortAscending = true;
    }
    notifyListeners();
  }

  void toggleModSelection(String modId, bool selected) {
    if (selected) {
      _selectedModIds.add(modId);
    } else {
      _selectedModIds.remove(modId);
    }
    notifyListeners();
  }

  void selectAll() {
    _selectedModIds
      ..clear()
      ..addAll((_scanResult?.entries ?? const []).map((e) => e.modInfo.id));
    notifyListeners();
  }

  void clearSelection() {
    _selectedModIds.clear();
    notifyListeners();
  }

  /// `{プロファイル}/mods/` をスキャンする(feature-spec.md §6.1)。
  Future<void> scan() async {
    final directory = _profileDirectory;
    if (directory == null) return;

    _state = ModTabState.scanning;
    _errorMessage = null;
    _lastResult = null;
    notifyListeners();

    try {
      final result = await _orchestrator.scan(
        profileDirectory: directory,
        targetLanguageId: _targetLanguageId,
      );
      _scanResult = result;
      _selectedModIds
        ..clear()
        ..addAll(result.entries.map((e) => e.modInfo.id));
      _state = ModTabState.scanned;
    } catch (e) {
      _errorMessage = 'スキャンに失敗しました: $e';
      _state = ModTabState.notSelected;
    }
    notifyListeners();
  }

  /// 選択された MOD を翻訳し、リソースパックを生成する(feature-spec.md §6.2)。
  Future<void> translate() async {
    final directory = _profileDirectory;
    final scan = _scanResult;
    if (directory == null || scan == null) return;

    final selected = scan.entries
        .where((e) => _selectedModIds.contains(e.modInfo.id))
        .toList();
    if (selected.isEmpty) return;

    final settings = _settingsController.settings;
    final apiKey = _settingsController.apiKeyFor(settings.llm.provider);
    final targetLanguage = settings.translation.allLanguages.firstWhere(
      (l) => l.id == _targetLanguageId,
      orElse: () => SupportedLanguage(
        id: _targetLanguageId,
        displayName: _targetLanguageId,
        isDefault: false,
      ),
    );

    _state = ModTabState.translating;
    _errorMessage = null;
    notifyListeners();

    try {
      final result = await _orchestrator.translateAndPack(
        profileDirectory: directory,
        selectedEntries: selected,
        targetLanguageId: _targetLanguageId,
        targetLanguageDisplayName: targetLanguage.displayName,
        settings: settings,
        apiKey: apiKey,
        sessionId: _sessionIdGenerator(),
      );
      _lastResult = result;
      _state = ModTabState.completed;
    } catch (e) {
      _errorMessage = '翻訳に失敗しました: $e';
      _state = ModTabState.scanned;
    }
    notifyListeners();
  }
}
