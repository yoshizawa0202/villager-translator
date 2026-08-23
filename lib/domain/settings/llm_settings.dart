import '../llm/default_prompts.dart';
import '../llm/llm_adapter_config.dart';
import '../llm/llm_provider.dart';
import '../llm/model_catalog.dart';
import '../llm/thinking_level.dart';

/// LLM プロバイダー・モデル・プロンプトに関する設定(feature-spec.md §4.1)。
///
/// API キーはここに含まれない。API キーはセキュアストレージ側でのみ管理する
/// (feature-spec.md §15)。
class LlmSettings {
  const LlmSettings({
    required this.provider,
    required this.model,
    required this.customModel,
    required this.maxRetries,
    required this.temperature,
    required this.systemPrompt,
    required this.userPrompt,
    required this.thinkingLevel,
    this.qwenBaseUrl = '',
  });

  final LlmProvider provider;

  /// [kModelCatalog] の値、または「カスタム」を表す [kCustomModelSentinel]。
  final String model;

  /// [model] が [kCustomModelSentinel] の場合に使う自由入力のモデル名。
  final String customModel;

  final int maxRetries;
  final double temperature;
  final String systemPrompt;
  final String userPrompt;

  /// 思考量(`docs/specs/009-thinking-level-setting.md`)。
  final ThinkingLevel thinkingLevel;

  /// Qwen API のベース URL の任意上書き(`docs/specs/010-additional-llm-providers.md` §9)。
  /// 空欄の場合は Qwen アダプターの既定(国際向けエンドポイント)を使う。
  final String qwenBaseUrl;

  /// 実際に API 呼び出しへ渡すモデル名。
  String get effectiveModel =>
      model == kCustomModelSentinel ? customModel : model;

  /// 選択中モデルの能力情報(010 §6.2)。UI・検証・アダプターはすべてこれを使う。
  ModelCapabilities get capabilities =>
      capabilitiesFor(provider, effectiveModel);

  /// [qwenBaseUrl] の前後空白を除いた値。空欄なら `null`。
  String? get normalizedQwenBaseUrl {
    final trimmed = qwenBaseUrl.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  /// アダプター生成に必要な設定を組み立てる(010 §7.3)。
  ///
  /// 4つの翻訳オーケストレーターと設定画面の接続確認は個別に設定を組み立てず、
  /// 必ずこのメソッドを使う。ベース URL の上書きは Qwen 選択時のみ渡し、
  /// 他プロバイダーのアダプターへは渡さない(010 AC-15)。
  LlmAdapterConfig toAdapterConfig({required String apiKey}) {
    return LlmAdapterConfig(
      apiKey: apiKey,
      model: effectiveModel,
      temperature: temperature,
      maxRetries: maxRetries,
      thinkingLevel: thinkingLevel,
      baseUrl: provider == LlmProvider.qwen ? normalizedQwenBaseUrl : null,
      capabilities: capabilities,
    );
  }

  static LlmSettings defaults() {
    const provider = LlmProvider.openai;
    return LlmSettings(
      provider: provider,
      model: kDefaultModel[provider]!,
      customModel: '',
      maxRetries: 3,
      temperature: 1.0,
      systemPrompt: kDefaultSystemPrompt,
      userPrompt: kDefaultUserPrompt,
      thinkingLevel: ThinkingLevel.off,
      qwenBaseUrl: '',
    );
  }

  LlmSettings copyWith({
    LlmProvider? provider,
    String? model,
    String? customModel,
    int? maxRetries,
    double? temperature,
    String? systemPrompt,
    String? userPrompt,
    ThinkingLevel? thinkingLevel,
    String? qwenBaseUrl,
  }) {
    return LlmSettings(
      provider: provider ?? this.provider,
      model: model ?? this.model,
      customModel: customModel ?? this.customModel,
      maxRetries: maxRetries ?? this.maxRetries,
      temperature: temperature ?? this.temperature,
      systemPrompt: systemPrompt ?? this.systemPrompt,
      userPrompt: userPrompt ?? this.userPrompt,
      thinkingLevel: thinkingLevel ?? this.thinkingLevel,
      qwenBaseUrl: qwenBaseUrl ?? this.qwenBaseUrl,
    );
  }

  Map<String, dynamic> toJson() => {
    'provider': provider.id,
    'model': model,
    'customModel': customModel,
    'maxRetries': maxRetries,
    'temperature': temperature,
    'systemPrompt': systemPrompt,
    'userPrompt': userPrompt,
    'thinkingLevel': thinkingLevel.id,
    'qwenBaseUrl': qwenBaseUrl,
  };

  /// JSON から復元する。欠損・不正な値はフィールド単位で既定値にフォールバックし、
  /// 例外を投げない(壊れた設定ファイルでも起動を継続できるようにするため)。
  factory LlmSettings.fromJson(Map<String, dynamic> json) {
    final fallback = LlmSettings.defaults();

    LlmProvider resolvedProvider;
    try {
      resolvedProvider = LlmProvider.fromId(json['provider'] as String? ?? '');
    } catch (_) {
      resolvedProvider = fallback.provider;
    }

    ThinkingLevel resolvedThinkingLevel;
    try {
      resolvedThinkingLevel = ThinkingLevel.fromId(
        json['thinkingLevel'] as String? ?? '',
      );
    } catch (_) {
      resolvedThinkingLevel = fallback.thinkingLevel;
    }

    return LlmSettings(
      provider: resolvedProvider,
      model: json['model'] as String? ?? kDefaultModel[resolvedProvider]!,
      customModel: json['customModel'] as String? ?? fallback.customModel,
      maxRetries: (json['maxRetries'] as num?)?.toInt() ?? fallback.maxRetries,
      temperature:
          (json['temperature'] as num?)?.toDouble() ?? fallback.temperature,
      systemPrompt: json['systemPrompt'] as String? ?? fallback.systemPrompt,
      userPrompt: json['userPrompt'] as String? ?? fallback.userPrompt,
      thinkingLevel: resolvedThinkingLevel,
      qwenBaseUrl: json['qwenBaseUrl'] as String? ?? fallback.qwenBaseUrl,
    );
  }
}
