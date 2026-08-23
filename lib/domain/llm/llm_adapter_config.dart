import 'model_catalog.dart';
import 'thinking_level.dart';

/// LLM アダプターの生成に必要な設定値。
///
/// API キーはこのオブジェクトを通じて呼び出し時にのみ渡され、
/// 設定ファイル(JSON)には保存しない(feature-spec.md §15)。
///
/// 生成は `LlmSettings.toAdapterConfig()` の1か所へ集約する
/// (`docs/specs/010-additional-llm-providers.md` §7.3)。
class LlmAdapterConfig {
  const LlmAdapterConfig({
    required this.apiKey,
    required this.model,
    required this.temperature,
    required this.maxRetries,
    this.thinkingLevel = ThinkingLevel.off,
    this.baseUrl,
    this.capabilities = kUnknownModelCapabilities,
  });

  final String apiKey;
  final String model;
  final double temperature;

  /// `docs/specs/003-translation-engine.md` のリトライループが参照する値。
  /// 本仕様(002)のアダプター骨組み自体はリトライを行わない。
  final int maxRetries;

  /// 思考量(`docs/specs/009-thinking-level-setting.md`)。
  /// `off` の場合、各アダプターは思考量関連のパラメータを一切送信しない。
  final ThinkingLevel thinkingLevel;

  /// ベース URL の任意上書き(010 §9)。`null` または空文字の場合、各アダプターは
  /// 自身の既定エンドポイントを使う。現状は Qwen アダプターのみに渡す。
  final String? baseUrl;

  /// 選択中モデルの能力情報(010 §6.2)。アダプターは `temperature` を送信して
  /// よいかどうかなどをここから判断し、モデル ID の条件分岐を持たない。
  final ModelCapabilities capabilities;
}
