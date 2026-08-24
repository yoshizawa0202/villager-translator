import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../domain/common/cancellation_token.dart';
import '../../domain/common/session_id.dart';
import '../../domain/common/translation_progress.dart';
import '../../domain/instancetranslation/instance_translation_estimate.dart';
import '../../domain/instancetranslation/instance_translation_mode.dart';
import '../../domain/instancetranslation/instance_translation_outcome.dart';
import '../../domain/instancetranslation/instance_translation_plan.dart';
import '../../domain/instancetranslation/resource_pack_format.dart';
import '../../domain/llm/llm_provider.dart';
import '../../domain/llm/model_catalog.dart';
import '../../domain/minecraftinstance/instance_analysis.dart';
import '../../domain/settings/supported_language.dart';
import '../../infrastructure/common/session_logger.dart';
import '../../infrastructure/common/system_notifier.dart';
import '../../infrastructure/instancetranslation/instance_translation_orchestrator.dart';
import '../settings/settings_controller.dart';

/// 一括翻訳画面の状態遷移(012-instance-batch-translation.md §3、§9、§10)。
enum InstanceTranslationState { ready, translating, completed }

/// インスタンス一括翻訳画面の状態を保持し、計画の組み立て・実行・結果集約を
/// 統括する(§3〜§12)。
///
/// この画面での選択(言語・プロバイダー・モデル・翻訳モード)はその実行だけの
/// 上書きとし、保存済み設定([SettingsController.save])は呼ばない(AC-04)。
class InstanceTranslationController extends ChangeNotifier {
  InstanceTranslationController({
    required SettingsController settingsController,
    required InstanceAnalysis analysis,
    InstanceTranslationOrchestrator? orchestrator,
    String Function()? sessionIdGenerator,
    SessionLogger? sessionLogger,
    Directory? applicationSupportDirectory,
    SystemNotifier? systemNotifier,
    String? targetLanguageId,
  }) : _settingsController = settingsController,
       _analysis = analysis,
       _orchestrator = orchestrator ?? InstanceTranslationOrchestrator(),
       _sessionIdGenerator = sessionIdGenerator ?? defaultSessionId,
       _sessionLogger =
           sessionLogger ??
           SessionLogger(
             applicationSupportDirectory: applicationSupportDirectory,
           ),
       _systemNotifier = systemNotifier ?? const NoopSystemNotifier(),
       _targetLanguageId = targetLanguageId ?? kDefaultLanguages.first.id,
       _provider = settingsController.settings.llm.provider,
       _model = settingsController.settings.llm.effectiveModel,
       _mode = InstanceTranslationMode.fromPolicy(
         settingsController.settings.translation.existingTranslationPolicy,
       ) {
    // 0 件のカテゴリは選択不可とし、既定でも OFF にする(§3、AC-02)。
    _translateMods = analysis.mods.isNotEmpty;
    _translateQuests = analysis.quests.isNotEmpty;
    _translateGuidebooks = analysis.guidebooks.isNotEmpty;
  }

  final SettingsController _settingsController;
  final InstanceTranslationOrchestrator _orchestrator;
  final String Function() _sessionIdGenerator;
  final SessionLogger _sessionLogger;
  final SystemNotifier _systemNotifier;

  SessionLogger get sessionLogger => _sessionLogger;

  InstanceAnalysis _analysis;
  InstanceAnalysis get analysis => _analysis;

  String _targetLanguageId;
  String get targetLanguageId => _targetLanguageId;

  LlmProvider _provider;
  LlmProvider get provider => _provider;

  String _model;
  String get model => _model;

  InstanceTranslationMode _mode;
  InstanceTranslationMode get mode => _mode;

  late bool _translateMods;
  bool get translateMods => _translateMods;

  late bool _translateQuests;
  bool get translateQuests => _translateQuests;

  late bool _translateGuidebooks;
  bool get translateGuidebooks => _translateGuidebooks;

  InstanceTranslationState _state = InstanceTranslationState.ready;
  InstanceTranslationState get state => _state;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  InstanceTranslationOutcome? _lastOutcome;
  InstanceTranslationOutcome? get lastOutcome => _lastOutcome;

  /// カテゴリ別進捗(§9)。
  final Map<InstanceTranslationCategory, OverallProgress> _categoryProgress =
      {};
  OverallProgress? progressFor(InstanceTranslationCategory category) =>
      _categoryProgress[category];

  ChunkProgress? _singleFileProgress;
  ChunkProgress? get singleFileProgress => _singleFileProgress;

  String? _currentItemName;
  String? get currentItemName => _currentItemName;

  InstanceTranslationCategory? _currentCategory;
  InstanceTranslationCategory? get currentCategory => _currentCategory;

  CancellationToken? _cancellationToken;
  bool get isCancelling => _cancellationToken?.isCancelled ?? false;

  /// 選択したモデルで生成される `pack_format`(§11)。
  ResourcePackFormatResolution get packFormat =>
      resolveResourcePackFormat(_analysis.instance.minecraftVersion);

  /// 全体進捗(全カテゴリの完了件数の合算、§9、AC-10)。
  OverallProgress get overallProgress {
    var completed = 0;
    var total = 0;
    for (final progress in _categoryProgress.values) {
      completed += progress.completedItems;
      total += progress.totalItems;
    }
    return OverallProgress(completedItems: completed, totalItems: total);
  }

  /// 現在の選択から翻訳計画を組み立てる(§2)。
  InstanceTranslationPlan buildPlan() {
    final language = _settingsController.settings.translation.allLanguages
        .firstWhere(
          (l) => l.id == _targetLanguageId,
          orElse: () => SupportedLanguage(
            id: _targetLanguageId,
            displayName: _targetLanguageId,
            isDefault: false,
          ),
        );

    return InstanceTranslationPlan(
      instance: _analysis.instance,
      targetLanguageId: _targetLanguageId,
      targetLanguageDisplayName: language.displayName,
      translateMods: _translateMods,
      translateQuests: _translateQuests,
      translateGuidebooks: _translateGuidebooks,
      mods: _analysis.mods,
      quests: _analysis.quests,
      guidebooks: _analysis.guidebooks,
      mode: _mode,
      provider: _provider,
      model: _model,
    );
  }

  /// 翻訳前サマリーの集計(§6)。
  InstanceTranslationEstimate buildEstimate() =>
      estimateInstanceTranslation(buildPlan());

  /// カテゴリを 1 件でも選択しており、実行できる状態かどうか(AC-02)。
  bool get canTranslate =>
      _state != InstanceTranslationState.translating &&
      buildPlan().hasAnyTarget;

  /// 解析結果を差し替える(対象言語の変更で再解析した場合)。
  void updateAnalysis(InstanceAnalysis analysis) {
    _analysis = analysis;
    if (analysis.mods.isEmpty) _translateMods = false;
    if (analysis.quests.isEmpty) _translateQuests = false;
    if (analysis.guidebooks.isEmpty) _translateGuidebooks = false;
    notifyListeners();
  }

  void setTargetLanguageId(String languageId) {
    _targetLanguageId = languageId;
    notifyListeners();
  }

  /// プロバイダーを変更する。モデルはそのプロバイダーの既定モデルへ切り替える
  /// (選択肢は既存のモデルカタログから導出する、AC-05)。
  void setProvider(LlmProvider provider) {
    _provider = provider;
    _model = kDefaultModel[provider] ?? _model;
    notifyListeners();
  }

  void setModel(String model) {
    _model = model;
    notifyListeners();
  }

  void setMode(InstanceTranslationMode mode) {
    _mode = mode;
    notifyListeners();
  }

  void setTranslateMods(bool value) {
    if (_analysis.mods.isEmpty) return;
    _translateMods = value;
    notifyListeners();
  }

  void setTranslateQuests(bool value) {
    if (_analysis.quests.isEmpty) return;
    _translateQuests = value;
    notifyListeners();
  }

  void setTranslateGuidebooks(bool value) {
    if (_analysis.guidebooks.isEmpty) return;
    _translateGuidebooks = value;
    notifyListeners();
  }

  /// 一括翻訳を実行する(§7〜§12)。
  ///
  /// [plan] を省略した場合は現在の選択から組み立てる。失敗項目の再試行では
  /// [buildRetryPlan] で絞り込んだ計画を渡し、同じ実行経路を再利用する(§10)。
  Future<void> translate({InstanceTranslationPlan? plan}) async {
    final target = plan ?? buildPlan();
    if (!target.hasAnyTarget) return;

    final apiKey = _settingsController.apiKeyFor(target.provider);
    if (apiKey.trim().isEmpty) {
      _errorMessage =
          '${target.provider.displayName} の API キーが未設定です。設定画面で登録してください。';
      notifyListeners();
      return;
    }

    final profileDirectory = Directory(target.instance.rootPath);
    final sessionId = _sessionIdGenerator();
    final token = CancellationToken();
    _cancellationToken = token;
    _categoryProgress.clear();
    _singleFileProgress = null;
    _currentItemName = null;
    _currentCategory = null;
    _errorMessage = null;
    _state = InstanceTranslationState.translating;
    notifyListeners();

    // 1 回の一括翻訳を 1 セッションとして扱い、3 カテゴリで sessionId を共有する
    // (§8)。API キー・Authorization ヘッダー・HTTP 応答本文は記録しない(AC-17)。
    await _sessionLogger.beginSession(
      profileDirectory: profileDirectory,
      sessionId: sessionId,
    );
    _sessionLogger.logTranslationStart(
      itemCount:
          target.effectiveMods.length +
          target.effectiveQuests.length +
          target.effectiveGuidebooks.length,
      targetLanguageId: target.targetLanguageId,
      provider: target.provider,
      model: target.model,
    );

    try {
      final outcome = await _orchestrator.translate(
        plan: target,
        settings: _settingsController.settings,
        apiKey: apiKey,
        sessionId: sessionId,
        cancellationToken: token,
        onCategoryStarted: (category) {
          _currentCategory = category;
          _sessionLogger.log(
            LogLevel.info,
            'translate.category',
            '${category.displayName} の翻訳を開始しました',
            isMilestone: true,
          );
          notifyListeners();
        },
        onCategoryProgress: (category, progress) {
          _categoryProgress[category] = progress;
          notifyListeners();
        },
        onSingleFileProgress: (progress) {
          _singleFileProgress = progress;
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

      _lastOutcome = outcome;
      _state = InstanceTranslationState.completed;
      _logCompletion(outcome);
      await _systemNotifier.showTranslationCompleted(
        title: '${target.instance.name} の一括翻訳が完了しました',
        body:
            '成功 ${outcome.successCount} / 失敗 ${outcome.failureCount} / '
            'スキップ ${outcome.skippedCount} 件',
      );
    } catch (e) {
      _errorMessage = '一括翻訳に失敗しました: $e';
      _state = InstanceTranslationState.ready;
      _sessionLogger.log(
        LogLevel.error,
        'translate',
        _errorMessage!,
        isMilestone: true,
      );
    } finally {
      _cancellationToken = null;
      _currentItemName = null;
      _currentCategory = null;
      await _sessionLogger.endSession();
    }
    notifyListeners();
  }

  /// 失敗した対象だけを再実行する(§10、AC-13)。新しい `sessionId` で実行し、
  /// 元のセッションのログ・バックアップを上書きしない。
  Future<void> retryFailed() async {
    final outcome = _lastOutcome;
    if (outcome == null || !outcome.hasFailures) return;
    await translate(plan: buildRetryPlan(buildPlan(), outcome));
  }

  /// 実行中の一括翻訳をキャンセルする(§9、AC-11)。
  void cancel() {
    _cancellationToken?.cancel();
    notifyListeners();
  }

  void _logCompletion(InstanceTranslationOutcome outcome) {
    _sessionLogger.logSummaryItems(outcome.summary);
    for (final category in outcome.categories) {
      if (category.error == null) continue;
      _sessionLogger.log(
        LogLevel.error,
        'translate.category',
        '${category.category.displayName} の翻訳に失敗しました: ${category.error}',
        isMilestone: true,
      );
    }
    _sessionLogger.log(
      LogLevel.info,
      'translate',
      '${outcome.cancelled ? '一括翻訳をキャンセルしました' : '一括翻訳が完了しました'}'
          '(成功 ${outcome.successCount} / 失敗 ${outcome.failureCount} / '
          'スキップ ${outcome.skippedCount})',
      isMilestone: true,
    );
  }

  @override
  void dispose() {
    _sessionLogger.dispose();
    super.dispose();
  }
}
