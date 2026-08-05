import 'package:flutter/foundation.dart';

import '../../domain/llm/llm_adapter_config.dart';
import '../../domain/llm/llm_provider.dart';
import '../../domain/llm/model_catalog.dart';
import '../../domain/settings/app_settings.dart';
import '../../domain/settings/llm_settings.dart';
import '../../domain/settings/settings_validator.dart';
import '../../domain/settings/supported_language.dart';
import '../../domain/settings/translation_settings.dart';
import '../../infrastructure/llm/llm_adapter_factory.dart';
import '../../infrastructure/settings/api_key_store.dart';
import '../../infrastructure/settings/settings_repository.dart';

/// 設定画面の状態を保持し、検証・保存・API キー管理を統括する。
///
/// 各更新メソッドは変更を即座に検証するが、有効な値は画面内の編集中の状態
/// ([settings] が返すドラフト)にのみ反映され、JSON ファイル / セキュアストレージ
/// へは [save] を明示的に呼び出したときにのみ書き込まれる(#9、#11)。
/// これは Enter 確定のたびに即時保存する方式が、Flutter が `onFieldSubmitted` /
/// `onEditingComplete` を同一の確定操作に対して両方発火させることに起因する
/// 保存処理の競合(設定ファイルの一時ファイルの二重リネーム)を招いたための変更。
/// 無効な値は保持・保存されず、エラーメッセージを返す。
///
/// 例外として [setThemeMode] と [resetToDefaults] は、それ自体が明示的な確定
/// 操作であるため保存ボタンを介さず即時に永続化する。
class SettingsController extends ChangeNotifier {
  SettingsController({
    required SettingsRepository repository,
    required ApiKeyStore apiKeyStore,
    LlmAdapterFactory? adapterFactory,
    DateTime Function()? clock,
  }) : _repository = repository,
       _apiKeyStore = apiKeyStore,
       _adapterFactory = adapterFactory ?? DefaultLlmAdapterFactory(),
       _clock = clock ?? DateTime.now;

  final SettingsRepository _repository;
  final ApiKeyStore _apiKeyStore;
  final LlmAdapterFactory _adapterFactory;
  final DateTime Function() _clock;

  /// ディスクに永続化済みの設定値。[setThemeMode] のようにドラフトの状態に
  /// かかわらず即時永続化する操作の起点として使い、[save] 前の未保存編集
  /// 内容を巻き込まないようにする。
  AppSettings _persisted = AppSettings.defaults();

  /// 画面で編集中のドラフト設定値。[save] を呼ぶまでディスクへは反映されない。
  AppSettings _settings = AppSettings.defaults();
  AppSettings get settings => _settings;

  /// ドラフトに永続化していない変更があるかどうか。
  /// 設定画面の保存状態インジケーターや、画面を閉じる際の警告ダイアログに使う。
  bool get hasUnsavedChanges => _hasUnsavedChanges;
  bool _hasUnsavedChanges = false;

  /// 直近で保存(設定ファイル / セキュアストレージへの書き込み)が完了した日時。
  /// 未保存(読み込み直後で一度も保存していない)場合は `null`。
  /// 設定画面の保存状態インジケーターに用いる(#9)。
  DateTime? _lastSavedAt;
  DateTime? get lastSavedAt => _lastSavedAt;

  void _markSaved() {
    _lastSavedAt = _clock();
  }

  /// 画面で編集中の API キーのドラフト値。
  final Map<LlmProvider, String> _apiKeys = {
    for (final provider in LlmProvider.values) provider: '',
  };

  /// セキュアストレージに永続化済みの API キー値。[discardChanges] で
  /// ドラフトを戻す先として使う。
  final Map<LlmProvider, String> _persistedApiKeys = {
    for (final provider in LlmProvider.values) provider: '',
  };

  /// [save] 時にセキュアストレージへ書き込むべき(まだ保存していない)
  /// API キーのプロバイダー集合。
  final Set<LlmProvider> _dirtyApiKeyProviders = {};

  bool _isLoaded = false;
  bool get isLoaded => _isLoaded;

  /// 保存済みの API キーを返す(復号済み・平文)。表示切替は UI 側で行う。
  String apiKeyFor(LlmProvider provider) => _apiKeys[provider] ?? '';

  /// 設定ファイルとセキュアストレージから状態を読み込む。
  Future<void> load() async {
    _persisted = await _repository.load();
    _settings = _persisted;
    for (final provider in LlmProvider.values) {
      final key = await _apiKeyStore.read(provider) ?? '';
      _apiKeys[provider] = key;
      _persistedApiKeys[provider] = key;
    }
    _dirtyApiKeyProviders.clear();
    _hasUnsavedChanges = false;
    _isLoaded = true;
    notifyListeners();
  }

  /// プロバイダーを切り替える。モデルはそのプロバイダーの既定モデルへリセットする。
  Future<String?> setProvider(LlmProvider provider) {
    return updateLlm(
      (llm) => llm.copyWith(
        provider: provider,
        model: kDefaultModel[provider]!,
        customModel: '',
      ),
    );
  }

  /// LLM 設定のドラフトを更新する。検証に失敗した場合はエラーメッセージを返し、
  /// ドラフトへ反映しない。ディスクへの永続化は [save] を呼ぶまで行われない。
  Future<String?> updateLlm(
    LlmSettings Function(LlmSettings current) update,
  ) async {
    final updated = update(_settings.llm);
    final error = _validateLlm(updated);
    if (error != null) return error;

    _settings = _settings.copyWith(llm: updated);
    _hasUnsavedChanges = true;
    notifyListeners();
    return null;
  }

  /// 翻訳設定のドラフトを更新する。検証に失敗した場合はエラーメッセージを返し、
  /// ドラフトへ反映しない。ディスクへの永続化は [save] を呼ぶまで行われない。
  Future<String?> updateTranslation(
    TranslationSettings Function(TranslationSettings current) update,
  ) async {
    final updated = update(_settings.translation);
    final error = _validateTranslation(updated);
    if (error != null) return error;

    _settings = _settings.copyWith(translation: updated);
    _hasUnsavedChanges = true;
    notifyListeners();
    return null;
  }

  /// カスタム言語を追加する。ID・表示名の検証に失敗した場合はエラーメッセージを返す。
  Future<String?> addCustomLanguage(String id, String displayName) {
    final normalizedId = id.trim().toLowerCase();
    final trimmedName = displayName.trim();
    final error = SettingsValidator.validateCustomLanguage(
      normalizedId,
      trimmedName,
      _settings.translation.allLanguages,
    );
    if (error != null) return Future.value(error);

    final updated = [
      ..._settings.translation.customLanguages,
      SupportedLanguage(
        id: normalizedId,
        displayName: trimmedName,
        isDefault: false,
      ),
    ];
    return updateTranslation((t) => t.copyWith(customLanguages: updated));
  }

  /// カスタム言語を削除する。既定言語は対象外(呼び出し元 UI が削除操作自体を出さない)。
  Future<void> removeCustomLanguage(String id) async {
    final updated = _settings.translation.customLanguages
        .where((lang) => lang.id != id)
        .toList();
    await updateTranslation((t) => t.copyWith(customLanguages: updated));
  }

  /// API キーのドラフトを更新する。セキュアストレージへの永続化は [save] を
  /// 呼ぶまで行われない。
  Future<void> setApiKey(LlmProvider provider, String apiKey) async {
    _apiKeys[provider] = apiKey;
    _dirtyApiKeyProviders.add(provider);
    _hasUnsavedChanges = true;
    notifyListeners();
  }

  /// テーマ切替(feature-spec.md §3.1)を設定・即時保存する。
  ///
  /// メインシェル画面のトグルから行う独立した操作であり、見た目のプレビュー性を
  /// 優先して保存ボタンを介さず即時に永続化する。[_persisted] を起点に保存する
  /// ことで、設定画面で編集中の未保存ドラフトを巻き込まない。
  Future<void> setThemeMode(AppThemeMode mode) async {
    _persisted = _persisted.copyWith(themeMode: mode);
    _settings = _settings.copyWith(themeMode: mode);
    await _repository.save(_persisted);
    _markSaved();
    notifyListeners();
  }

  /// LLM 設定・翻訳設定を初期値へリセットする。保存済みの API キーには触れない
  /// (受け入れ条件5)。現在選択中のプロバイダーは変更しない。プロバイダーを
  /// 初期値(OpenAI)へ戻してしまうと、API キー入力欄が別プロバイダーの
  /// (未設定の)キーへ切り替わり、保持しているはずの API キーが画面上から
  /// 消えたように見えてしまうため。現在のテーマ設定には影響しない。それ自体が
  /// 明示的な確定操作であるため、保存ボタンを介さず即時に永続化する。
  Future<void> resetToDefaults() async {
    final currentProvider = _settings.llm.provider;
    final llmDefaults = LlmSettings.defaults().copyWith(
      provider: currentProvider,
      model: kDefaultModel[currentProvider]!,
    );
    final defaults = AppSettings.defaults().copyWith(
      llm: llmDefaults,
      themeMode: _persisted.themeMode,
    );
    _settings = defaults;
    _persisted = defaults;
    await _repository.save(_persisted);
    _markSaved();
    _hasUnsavedChanges = false;
    notifyListeners();
  }

  /// 編集中のドラフト(LLM 設定・翻訳設定・プロンプト・変更のあった API キー)を
  /// まとめて設定ファイル・セキュアストレージへ永続化する(保存ボタン)。
  Future<void> save() async {
    _persisted = _settings;
    await _repository.save(_persisted);
    for (final provider in _dirtyApiKeyProviders) {
      final value = _apiKeys[provider] ?? '';
      await _apiKeyStore.write(provider, value);
      _persistedApiKeys[provider] = value;
    }
    _dirtyApiKeyProviders.clear();
    _hasUnsavedChanges = false;
    _markSaved();
    notifyListeners();
  }

  /// 保存していないドラフトの変更を破棄し、直近に永続化された状態へ戻す。
  /// 設定画面を「破棄して閉じる」場合に使う。
  void discardChanges() {
    _settings = _persisted;
    for (final provider in _dirtyApiKeyProviders) {
      _apiKeys[provider] = _persistedApiKeys[provider] ?? '';
    }
    _dirtyApiKeyProviders.clear();
    _hasUnsavedChanges = false;
    notifyListeners();
  }

  /// [candidateApiKey] の有効性を、保存前でも軽量な API 呼び出しで検証する。
  Future<bool> testApiKey(LlmProvider provider, String candidateApiKey) {
    final adapter = _adapterFactory.create(
      provider,
      LlmAdapterConfig(
        apiKey: candidateApiKey,
        model: _settings.llm.effectiveModel,
        temperature: _settings.llm.temperature,
        maxRetries: _settings.llm.maxRetries,
      ),
    );
    return adapter.validateApiKey(candidateApiKey);
  }

  String? _validateLlm(LlmSettings s) {
    return SettingsValidator.validateTemperature(s.temperature) ??
        SettingsValidator.validateMaxRetries(s.maxRetries) ??
        SettingsValidator.validateCustomModel(s.model, s.customModel);
  }

  String? _validateTranslation(TranslationSettings s) {
    return SettingsValidator.validateMaxTokensPerChunk(s.maxTokensPerChunk) ??
        SettingsValidator.validateChunkSize(s.modChunkSize) ??
        SettingsValidator.validateChunkSize(s.questChunkSize) ??
        SettingsValidator.validateChunkSize(s.guidebookChunkSize);
  }
}
