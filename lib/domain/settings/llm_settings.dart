import '../llm/default_prompts.dart';
import '../llm/llm_provider.dart';
import '../llm/model_catalog.dart';

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

  /// 実際に API 呼び出しへ渡すモデル名。
  String get effectiveModel =>
      model == kCustomModelSentinel ? customModel : model;

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
  }) {
    return LlmSettings(
      provider: provider ?? this.provider,
      model: model ?? this.model,
      customModel: customModel ?? this.customModel,
      maxRetries: maxRetries ?? this.maxRetries,
      temperature: temperature ?? this.temperature,
      systemPrompt: systemPrompt ?? this.systemPrompt,
      userPrompt: userPrompt ?? this.userPrompt,
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

    return LlmSettings(
      provider: resolvedProvider,
      model: json['model'] as String? ?? kDefaultModel[resolvedProvider]!,
      customModel: json['customModel'] as String? ?? fallback.customModel,
      maxRetries: (json['maxRetries'] as num?)?.toInt() ?? fallback.maxRetries,
      temperature:
          (json['temperature'] as num?)?.toDouble() ?? fallback.temperature,
      systemPrompt: json['systemPrompt'] as String? ?? fallback.systemPrompt,
      userPrompt: json['userPrompt'] as String? ?? fallback.userPrompt,
    );
  }
}
