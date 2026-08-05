import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../domain/common/cancellation_token.dart';
import '../../domain/common/session_id.dart';
import '../../domain/common/translation_progress.dart';
import '../../domain/settings/supported_language.dart';
import '../../infrastructure/common/session_logger.dart';
import '../../infrastructure/common/system_notifier.dart';
import '../../infrastructure/patchoulitranslation/patchouli_translation_orchestrator.dart';
import '../settings/settings_controller.dart';
import '../shell/profile_directory_controller.dart';

/// Patchouli タブの状態遷移(`004-mod-translation.md` の MOD タブと同様の方針)。
///
/// 未選択→スキャン中→スキャン完了→翻訳中→完了、の単一タブ内の遷移のみを扱う
/// (他タブとの排他制御は `008` で統合する)。
enum PatchouliTabState {
  notSelected,
  scanning,
  scanned,
  translating,
  completed,
}

/// テーブルのソート対象列。
enum PatchouliTableSortColumn { book, path, fileCount }

/// Patchouli タブの状態を保持し、スキャン・選択・翻訳を統括する
/// (feature-spec.md §8)。
class PatchouliTranslationController extends ChangeNotifier {
  PatchouliTranslationController({
    required SettingsController settingsController,
    PatchouliTranslationOrchestrator? orchestrator,
    String Function()? sessionIdGenerator,
    SessionLogger? sessionLogger,
    Directory? applicationSupportDirectory,
    SystemNotifier? systemNotifier,
    ProfileDirectoryController? profileDirectoryController,
  }) : _settingsController = settingsController,
       _orchestrator = orchestrator ?? PatchouliTranslationOrchestrator(),
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
  final PatchouliTranslationOrchestrator _orchestrator;
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

  PatchouliTabState _state = PatchouliTabState.notSelected;
  PatchouliTabState get state => _state;

  Directory? get profileDirectory =>
      _profileDirectoryController.profileDirectory;

  PatchouliScanResult? _scanResult;
  PatchouliScanResult? get scanResult => _scanResult;

  final Set<String> _selectedBookKeys = {};
  Set<String> get selectedBookKeys => Set.unmodifiable(_selectedBookKeys);

  /// Patchouli タブ専用の対象言語選択状態。
  String _targetLanguageId = kDefaultLanguages.first.id;
  String get targetLanguageId => _targetLanguageId;

  String _searchQuery = '';
  String get searchQuery => _searchQuery;

  PatchouliTableSortColumn _sortColumn = PatchouliTableSortColumn.book;
  PatchouliTableSortColumn get sortColumn => _sortColumn;

  bool _sortAscending = true;
  bool get sortAscending => _sortAscending;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  PatchouliTranslateAndWriteResult? _lastResult;
  PatchouliTranslateAndWriteResult? get lastResult => _lastResult;

  /// 検索・ソートを適用したテーブル表示用の一覧。
  List<PatchouliBookEntry> get visibleEntries {
    final entries = _scanResult?.entries ?? const <PatchouliBookEntry>[];
    final query = _searchQuery.trim().toLowerCase();
    final filtered = query.isEmpty
        ? entries.toList()
        : entries
              .where((e) => e.bookKey.toLowerCase().contains(query))
              .toList();

    int compare(PatchouliBookEntry a, PatchouliBookEntry b) {
      switch (_sortColumn) {
        case PatchouliTableSortColumn.book:
          return a.bookKey.compareTo(b.bookKey);
        case PatchouliTableSortColumn.path:
          return a.jarRelativePath.compareTo(b.jarRelativePath);
        case PatchouliTableSortColumn.fileCount:
          return a.files.length.compareTo(b.files.length);
      }
    }

    filtered.sort(_sortAscending ? compare : (a, b) => compare(b, a));
    return filtered;
  }

  /// プロファイルディレクトリを設定する(全タブで共有、feature-spec.md §3.2)。
  void setProfileDirectoryPath(String path) {
    _profileDirectoryController.setPath(path);
  }

  /// 共有プロファイルディレクトリの変更(このタブでの変更を含む)を受けて、
  /// 以前のスキャン結果・選択状態を破棄する。
  void _onProfileDirectoryChanged() {
    _scanResult = null;
    _selectedBookKeys.clear();
    _errorMessage = null;
    _state = PatchouliTabState.notSelected;
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

  void setSortColumn(PatchouliTableSortColumn column) {
    if (_sortColumn == column) {
      _sortAscending = !_sortAscending;
    } else {
      _sortColumn = column;
      _sortAscending = true;
    }
    notifyListeners();
  }

  void toggleBookSelection(String bookKey, bool selected) {
    if (selected) {
      _selectedBookKeys.add(bookKey);
    } else {
      _selectedBookKeys.remove(bookKey);
    }
    notifyListeners();
  }

  void selectAll() {
    _selectedBookKeys
      ..clear()
      ..addAll((_scanResult?.entries ?? const []).map((e) => e.bookKey));
    notifyListeners();
  }

  void clearSelection() {
    _selectedBookKeys.clear();
    notifyListeners();
  }

  /// `{プロファイル}/mods/` をスキャンする(feature-spec.md §8.1)。
  Future<void> scan() async {
    final directory = profileDirectory;
    if (directory == null) return;

    _state = PatchouliTabState.scanning;
    _errorMessage = null;
    _lastResult = null;
    notifyListeners();

    try {
      final result = await _orchestrator.scan(
        profileDirectory: directory,
        targetLanguageId: _targetLanguageId,
      );
      _scanResult = result;
      _selectedBookKeys
        ..clear()
        ..addAll(result.entries.map((e) => e.bookKey));
      _state = PatchouliTabState.scanned;
    } catch (e) {
      _errorMessage = 'スキャンに失敗しました: $e';
      _state = PatchouliTabState.notSelected;
    }
    notifyListeners();
  }

  /// 選択された本を翻訳し、対応する JAR へ書き込む(feature-spec.md §8.2)。
  Future<void> translate() async {
    final directory = profileDirectory;
    final scan = _scanResult;
    if (directory == null || scan == null) return;

    final selected = scan.entries
        .where((e) => _selectedBookKeys.contains(e.bookKey))
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

    _state = PatchouliTabState.translating;
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
      _state = PatchouliTabState.completed;
      _sessionLogger.logSummaryItems(result.summary);
      _sessionLogger.log(
        LogLevel.info,
        'translate',
        '翻訳が完了しました(成功 ${result.summary.successCount} / '
            '失敗 ${result.summary.failureCount} / 合計 ${result.summary.totalCount})',
        isMilestone: true,
      );
      await _systemNotifier.showTranslationCompleted(
        title: 'ガイドブック翻訳が完了しました',
        body:
            '成功 ${result.summary.successCount} / 失敗 ${result.summary.failureCount} / '
            '合計 ${result.summary.totalCount} 件',
      );
    } catch (e) {
      _errorMessage = '翻訳に失敗しました: $e';
      _state = PatchouliTabState.scanned;
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
