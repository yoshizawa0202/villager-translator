import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../domain/common/cancellation_token.dart';
import '../../domain/common/session_id.dart';
import '../../domain/common/translation_progress.dart';
import '../../domain/settings/supported_language.dart';
import '../../infrastructure/common/session_logger.dart';
import '../../infrastructure/common/system_notifier.dart';
import '../../infrastructure/customfiletranslation/custom_file_translation_orchestrator.dart';
import '../settings/settings_controller.dart';
import '../shell/profile_directory_controller.dart';

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
    String Function()? sessionIdGenerator,
    SessionLogger? sessionLogger,
    Directory? applicationSupportDirectory,
    SystemNotifier? systemNotifier,
    ProfileDirectoryController? profileDirectoryController,
  }) : _settingsController = settingsController,
       _orchestrator = orchestrator ?? CustomFileTranslationOrchestrator(),
       _sessionIdGenerator = sessionIdGenerator ?? defaultSessionId,
       _sessionLogger =
           sessionLogger ??
           SessionLogger(
             applicationSupportDirectory: applicationSupportDirectory,
           ),
       _systemNotifier = systemNotifier ?? const NoopSystemNotifier(),
       _profileDirectoryController =
           profileDirectoryController ?? ProfileDirectoryController() {
    _profileDirectoryController.addListener(_onProfileDirectoryChanged);
  }

  final SettingsController _settingsController;
  final CustomFileTranslationOrchestrator _orchestrator;
  final String Function() _sessionIdGenerator;
  final SessionLogger _sessionLogger;
  final SystemNotifier _systemNotifier;
  final ProfileDirectoryController _profileDirectoryController;

  SessionLogger get sessionLogger => _sessionLogger;

  CancellationToken? _cancellationToken;

  OverallProgress? _overallProgress;
  OverallProgress? get overallProgress => _overallProgress;

  ChunkProgress? _singleFileProgress;
  ChunkProgress? get singleFileProgress => _singleFileProgress;

  /// 現在翻訳処理中の対象の表示名(ファイル相対パス、feature-spec.md §10、Issue #7)。
  String? _currentItemName;
  String? get currentItemName => _currentItemName;

  CustomFileTabState _state = CustomFileTabState.notSelected;
  CustomFileTabState get state => _state;

  Directory? get profileDirectory =>
      _profileDirectoryController.profileDirectory;

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

  /// プロファイルディレクトリを設定する(全タブで共有、feature-spec.md §3.2)。
  /// このディレクトリ配下を再帰的にスキャン対象とする。
  void setProfileDirectoryPath(String path) {
    _profileDirectoryController.setPath(path);
  }

  /// 共有プロファイルディレクトリの変更(このタブでの変更を含む)を受けて、
  /// 以前のスキャン結果・選択状態を破棄する。
  void _onProfileDirectoryChanged() {
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
    final directory = profileDirectory;
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
    final directory = profileDirectory;
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

    final sessionId = _sessionIdGenerator();
    final token = CancellationToken();
    _cancellationToken = token;
    _overallProgress = null;
    _singleFileProgress = null;
    _currentItemName = null;

    _state = CustomFileTabState.translating;
    _errorMessage = null;
    notifyListeners();

    await _sessionLogger.beginSession(
      profileDirectory: directory,
      sessionId: sessionId,
    );
    _sessionLogger.log(
      LogLevel.info,
      'translate',
      '翻訳を開始しました(対象 ${selected.length} 件、言語 $_targetLanguageId)',
      isMilestone: true,
    );

    try {
      final result = await _orchestrator.translateAndWrite(
        profileDirectory: directory,
        selectedEntries: selected,
        targetLanguageId: _targetLanguageId,
        targetLanguageDisplayName: targetLanguage.displayName,
        settings: settings,
        apiKey: apiKey,
        sessionId: sessionId,
        cancellationToken: token,
        onSingleFileProgress: (progress) {
          _singleFileProgress = progress;
          notifyListeners();
        },
        onOverallProgress: (progress) {
          _overallProgress = progress;
          _sessionLogger.log(LogLevel.info, 'translate', progress.label);
          notifyListeners();
        },
        onItemStarted: (itemName) {
          _currentItemName = itemName;
          notifyListeners();
        },
        onChunkResult: (itemLabel, chunkResult) {
          _sessionLogger.log(
            chunkResult.success
                ? (chunkResult.retryCount > 0
                      ? LogLevel.warning
                      : LogLevel.debug)
                : LogLevel.error,
            'translate.chunk',
            '[$itemLabel] チャンク ${chunkResult.chunkIndex + 1}/'
                '${chunkResult.totalChunks} '
                '${chunkResult.success ? '成功' : '失敗'}'
                '(${chunkResult.keyCount} キー、リトライ ${chunkResult.retryCount} 回)'
                '${chunkResult.error != null ? ': ${chunkResult.error}' : ''}',
          );
        },
      );
      _lastResult = result;
      _currentItemName = null;
      _state = CustomFileTabState.completed;
      _sessionLogger.logSummaryItems(result.summary);
      _sessionLogger.log(
        LogLevel.info,
        'translate',
        '翻訳が完了しました(成功 ${result.summary.successCount} / '
            '失敗 ${result.summary.failureCount} / 合計 ${result.summary.totalCount})',
        isMilestone: true,
      );
      await _systemNotifier.showTranslationCompleted(
        title: 'カスタムファイル翻訳が完了しました',
        body:
            '成功 ${result.summary.successCount} / 失敗 ${result.summary.failureCount} / '
            '合計 ${result.summary.totalCount} 件',
      );
    } catch (e) {
      _errorMessage = '翻訳に失敗しました: $e';
      _state = CustomFileTabState.scanned;
      _currentItemName = null;
      _sessionLogger.log(
        LogLevel.error,
        'translate',
        _errorMessage!,
        isMilestone: true,
      );
    } finally {
      _cancellationToken = null;
      await _sessionLogger.endSession();
    }
    notifyListeners();
  }

  /// 実行中の翻訳をキャンセルする(協調的キャンセル、feature-spec.md §10)。
  void cancel() {
    _cancellationToken?.cancel();
  }

  @override
  void dispose() {
    _profileDirectoryController.removeListener(_onProfileDirectoryChanged);
    _sessionLogger.dispose();
    super.dispose();
  }
}
