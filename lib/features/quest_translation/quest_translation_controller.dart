import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../domain/settings/supported_language.dart';
import '../../infrastructure/questtranslation/quest_translation_orchestrator.dart';
import '../settings/settings_controller.dart';

/// クエストタブの状態遷移(`004-mod-translation.md` の MOD タブと同様の方針)。
///
/// 未選択→スキャン中→スキャン完了→翻訳中→完了、の単一タブ内の遷移のみを扱う
/// (他タブとの排他制御は `008` で統合する)。
enum QuestTabState { notSelected, scanning, scanned, translating, completed }

/// テーブルのソート対象列。
enum QuestTableSortColumn { path, format }

String _defaultSessionId() =>
    DateTime.now().toIso8601String().replaceAll(RegExp(r'[:.]'), '-');

/// クエストタブの状態を保持し、スキャン・選択・翻訳を統括する
/// (feature-spec.md §7)。
class QuestTranslationController extends ChangeNotifier {
  QuestTranslationController({
    required SettingsController settingsController,
    QuestTranslationOrchestrator? orchestrator,
    String Function()? sessionIdGenerator,
  }) : _settingsController = settingsController,
       _orchestrator = orchestrator ?? QuestTranslationOrchestrator(),
       _sessionIdGenerator = sessionIdGenerator ?? _defaultSessionId;

  final SettingsController _settingsController;
  final QuestTranslationOrchestrator _orchestrator;
  final String Function() _sessionIdGenerator;

  QuestTabState _state = QuestTabState.notSelected;
  QuestTabState get state => _state;

  Directory? _profileDirectory;
  Directory? get profileDirectory => _profileDirectory;

  List<QuestScanEntry>? _scanResult;
  List<QuestScanEntry>? get scanResult => _scanResult;

  final Set<String> _selectedPaths = {};
  Set<String> get selectedPaths => Set.unmodifiable(_selectedPaths);

  /// クエストタブ専用の対象言語選択状態。
  String _targetLanguageId = kDefaultLanguages.first.id;
  String get targetLanguageId => _targetLanguageId;

  String _searchQuery = '';
  String get searchQuery => _searchQuery;

  QuestTableSortColumn _sortColumn = QuestTableSortColumn.path;
  QuestTableSortColumn get sortColumn => _sortColumn;

  bool _sortAscending = true;
  bool get sortAscending => _sortAscending;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  QuestTranslateAndWriteResult? _lastResult;
  QuestTranslateAndWriteResult? get lastResult => _lastResult;

  /// 検索・ソートを適用したテーブル表示用の一覧。
  List<QuestScanEntry> get visibleEntries {
    final entries = _scanResult ?? const <QuestScanEntry>[];
    final query = _searchQuery.trim().toLowerCase();
    final filtered = query.isEmpty
        ? entries.toList()
        : entries
              .where((e) => e.relativePath.toLowerCase().contains(query))
              .toList();

    int compare(QuestScanEntry a, QuestScanEntry b) {
      switch (_sortColumn) {
        case QuestTableSortColumn.path:
          return a.relativePath.compareTo(b.relativePath);
        case QuestTableSortColumn.format:
          return a.format.name.compareTo(b.format.name);
      }
    }

    filtered.sort(_sortAscending ? compare : (a, b) => compare(b, a));
    return filtered;
  }

  /// プロファイルディレクトリを設定する。以前のスキャン結果・選択状態は破棄する。
  void setProfileDirectoryPath(String path) {
    _profileDirectory = Directory(path);
    _scanResult = null;
    _selectedPaths.clear();
    _errorMessage = null;
    _state = QuestTabState.notSelected;
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

  void setSortColumn(QuestTableSortColumn column) {
    if (_sortColumn == column) {
      _sortAscending = !_sortAscending;
    } else {
      _sortColumn = column;
      _sortAscending = true;
    }
    notifyListeners();
  }

  void toggleQuestSelection(String relativePath, bool selected) {
    if (selected) {
      _selectedPaths.add(relativePath);
    } else {
      _selectedPaths.remove(relativePath);
    }
    notifyListeners();
  }

  void selectAll() {
    _selectedPaths
      ..clear()
      ..addAll((_scanResult ?? const []).map((e) => e.relativePath));
    notifyListeners();
  }

  void clearSelection() {
    _selectedPaths.clear();
    notifyListeners();
  }

  /// FTB Quests / Better Quests をスキャンする(feature-spec.md §7.1、§7.2)。
  Future<void> scan() async {
    final directory = _profileDirectory;
    if (directory == null) return;

    _state = QuestTabState.scanning;
    _errorMessage = null;
    _lastResult = null;
    notifyListeners();

    try {
      final entries = await _orchestrator.scan(profileDirectory: directory);
      _scanResult = entries;
      _selectedPaths
        ..clear()
        ..addAll(entries.map((e) => e.relativePath));
      _state = QuestTabState.scanned;
    } catch (e) {
      _errorMessage = 'スキャンに失敗しました: $e';
      _state = QuestTabState.notSelected;
    }
    notifyListeners();
  }

  /// 選択されたクエストファイルを翻訳し、出力先へ書き出す(feature-spec.md §7)。
  Future<void> translate() async {
    final directory = _profileDirectory;
    final scan = _scanResult;
    if (directory == null || scan == null) return;

    final selected = scan
        .where((e) => _selectedPaths.contains(e.relativePath))
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

    _state = QuestTabState.translating;
    _errorMessage = null;
    notifyListeners();

    try {
      final result = await _orchestrator.translateAndWrite(
        profileDirectory: directory,
        selectedEntries: selected,
        targetLanguageId: _targetLanguageId,
        targetLanguageDisplayName: targetLanguage.displayName,
        settings: settings,
        apiKey: apiKey,
        sessionId: _sessionIdGenerator(),
      );
      _lastResult = result;
      _state = QuestTabState.completed;
    } catch (e) {
      _errorMessage = '翻訳に失敗しました: $e';
      _state = QuestTabState.scanned;
    }
    notifyListeners();
  }
}
