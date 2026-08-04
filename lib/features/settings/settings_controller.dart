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

/// 設定画面の状態を保持し、検証・自動保存・API キー管理を統括する。
///
/// 各更新メソッドは変更を即座に検証し、有効な場合のみ JSON ファイル /
/// セキュアストレージへ反映する(自動保存方式)。無効な値は保持・保存されず、
/// エラーメッセージを返す。
class SettingsController extends ChangeNotifier {
  SettingsController({
    required SettingsRepository repository,
    required ApiKeyStore apiKeyStore,
    LlmAdapterFactory? adapterFactory,
  }) : _repository = repository,
       _apiKeyStore = apiKeyStore,
       _adapterFactory = adapterFactory ?? DefaultLlmAdapterFactory();

  final SettingsRepository _repository;
  final ApiKeyStore _apiKeyStore;
  final LlmAdapterFactory _adapterFactory;

  AppSettings _settings = AppSettings.defaults();
  AppSettings get settings => _settings;

  final Map<LlmProvider, String> _apiKeys = {
    for (final provider in LlmProvider.values) provider: '',
  };

  bool _isLoaded = false;
  bool get isLoaded => _isLoaded;

  /// 保存済みの API キーを返す(復号済み・平文)。表示切替は UI 側で行う。
  String apiKeyFor(LlmProvider provider) => _apiKeys[provider] ?? '';

  /// 設定ファイルとセキュアストレージから状態を読み込む。
  Future<void> load() async {
    _settings = await _repository.load();
    for (final provider in LlmProvider.values) {
      _apiKeys[provider] = await _apiKeyStore.read(provider) ?? '';
    }
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

  /// LLM 設定を更新する。検証に失敗した場合はエラーメッセージを返し、保存しない。
  Future<String?> updateLlm(
    LlmSettings Function(LlmSettings current) update,
  ) async {
    final updated = update(_settings.llm);
    final error = _validateLlm(updated);
    if (error != null) return error;

    _settings = _settings.copyWith(llm: updated);
    await _repository.save(_settings);
    notifyListeners();
    return null;
  }

  /// 翻訳設定を更新する。検証に失敗した場合はエラーメッセージを返し、保存しない。
  Future<String?> updateTranslation(
    TranslationSettings Function(TranslationSettings current) update,
  ) async {
    final updated = update(_settings.translation);
    final error = _validateTranslation(updated);
    if (error != null) return error;

    _settings = _settings.copyWith(translation: updated);
    await _repository.save(_settings);
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

  /// API キーをセキュアストレージへ保存する。
  Future<void> setApiKey(LlmProvider provider, String apiKey) async {
    await _apiKeyStore.write(provider, apiKey);
    _apiKeys[provider] = apiKey;
    notifyListeners();
  }

  /// テーマ切替(feature-spec.md §3.1)を設定・保存する。
  Future<void> setThemeMode(AppThemeMode mode) async {
    _settings = _settings.copyWith(themeMode: mode);
    await _repository.save(_settings);
    notifyListeners();
  }

  /// LLM 設定・翻訳設定を初期値へリセットする。保存済みの API キーには触れない
  /// (受け入れ条件5)。
  Future<void> resetToDefaults() async {
    _settings = AppSettings.defaults();
    await _repository.save(_settings);
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
