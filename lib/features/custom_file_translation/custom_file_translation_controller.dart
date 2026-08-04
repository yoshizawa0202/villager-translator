import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../domain/settings/supported_language.dart';
import '../../infrastructure/customfiletranslation/custom_file_translation_orchestrator.dart';
import '../settings/settings_controller.dart';

/// カスタムファイルタブの状態遷移(`004-mod-translation.md` の MOD タブと同様の方針)。
///
/// 未選択→スキャン中→スキャン完了→翻訳中→完了、の単一タブ内の遷移のみを扱う
/// (他タブとの排他制御は `008` で統合する)。
enum CustomFileTabState {
  notSelected,
  scanning,
  scanned,
  translating,
  completed,
}

/// テーブルのソート対象列。
enum CustomFileTableSortColumn { path, format }

/// カスタムファイルタブの状態を保持し、スキャン・選択・翻訳を統括する
/// (feature-spec.md §9)。
class CustomFileTranslationController extends ChangeNotifier {
  CustomFileTranslationController({
    required SettingsController settingsController,
    CustomFileTranslationOrchestrator? orchestrator,
  }) : _settingsController = settingsController,
       _orchestrator = orchestrator ?? CustomFileTranslationOrchestrator();

  final SettingsController _settingsController;
  final CustomFileTranslationOrchestrator _orchestrator;

  CustomFileTabState _state = CustomFileTabState.notSelected;
  CustomFileTabState get state => _state;

  Directory? _rootDirectory;
  Directory? get rootDirectory => _rootDirectory;

  List<CustomFileScanEntry>? _scanResult;
  List<CustomFileScanEntry>? get scanResult => _scanResult;

  final Set<String> _selectedPaths = {};
  Set<String> get selectedPaths => Set.unmodifiable(_selectedPaths);

  /// カスタムファイルタブ専用の対象言語選択状態。
  String _targetLanguageId = kDefaultLanguages.first.id;
  String get targetLanguageId => _targetLanguageId;

  String _searchQuery = '';
  String get searchQuery => _searchQuery;

  CustomFileTableSortColumn _sortColumn = CustomFileTableSortColumn.path;
  CustomFileTableSortColumn get sortColumn => _sortColumn;

  bool _sortAscending = true;
  bool get sortAscending => _sortAscending;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  CustomFileTranslateAndWriteResult? _lastResult;
  CustomFileTranslateAndWriteResult? get lastResult => _lastResult;

  /// 検索・ソートを適用したテーブル表示用の一覧。
  List<CustomFileScanEntry> get visibleEntries {
    final entries = _scanResult ?? const <CustomFileScanEntry>[];
    final query = _searchQuery.trim().toLowerCase();
    final filtered = query.isEmpty
        ? entries.toList()
        : entries
              .where((e) => e.relativePath.toLowerCase().contains(query))
              .toList();

    int compare(CustomFileScanEntry a, CustomFileScanEntry b) {
      switch (_sortColumn) {
        case CustomFileTableSortColumn.path:
          return a.relativePath.compareTo(b.relativePath);
        case CustomFileTableSortColumn.format:
          return a.format.name.compareTo(b.format.name);
      }
    }

    filtered.sort(_sortAscending ? compare : (a, b) => compare(b, a));
    return filtered;
  }

  /// スキャン対象のルートディレクトリを設定する。以前のスキャン結果・選択状態は破棄する。
  void setRootDirectoryPath(String path) {
    _rootDirectory = Directory(path);
    _scanResult = null;
    _selectedPaths.clear();
    _errorMessage = null;
    _state = CustomFileTabState.notSelected;
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

  void setSortColumn(CustomFileTableSortColumn column) {
    if (_sortColumn == column) {
      _sortAscending = !_sortAscending;
    } else {
      _sortColumn = column;
      _sortAscending = true;
    }
    notifyListeners();
  }

  void toggleFileSelection(String relativePath, bool selected) {
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

  /// ルートディレクトリ配下の `.json` `.snbt` を再帰的にスキャンする(feature-spec.md §9)。
  Future<void> scan() async {
    final directory = _rootDirectory;
    if (directory == null) return;

    _state = CustomFileTabState.scanning;
    _errorMessage = null;
    _lastResult = null;
    notifyListeners();

    try {
      final entries = await _orchestrator.scan(rootDirectory: directory);
      _scanResult = entries;
      _selectedPaths
        ..clear()
        ..addAll(entries.map((e) => e.relativePath));
      _state = CustomFileTabState.scanned;
    } catch (e) {
      _errorMessage = 'スキャンに失敗しました: $e';
      _state = CustomFileTabState.notSelected;
    }
    notifyListeners();
  }

  /// 選択されたカスタムファイルを翻訳し、`translated/` 配下へ書き出す(feature-spec.md §9)。
  Future<void> translate() async {
    final scan = _scanResult;
    if (scan == null) return;

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

    _state = CustomFileTabState.translating;
    _errorMessage = null;
    notifyListeners();

    try {
      final result = await _orchestrator.translateAndWrite(
        selectedEntries: selected,
        targetLanguageId: _targetLanguageId,
        targetLanguageDisplayName: targetLanguage.displayName,
        settings: settings,
        apiKey: apiKey,
      );
      _lastResult = result;
      _state = CustomFileTabState.completed;
    } catch (e) {
      _errorMessage = '翻訳に失敗しました: $e';
      _state = CustomFileTabState.scanned;
    }
    notifyListeners();
  }
}
