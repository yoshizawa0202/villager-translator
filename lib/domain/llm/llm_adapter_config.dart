/// LLM アダプターの生成に必要な設定値。
///
/// API キーはこのオブジェクトを通じて呼び出し時にのみ渡され、
/// 設定ファイル(JSON)には保存しない(feature-spec.md §15)。
class LlmAdapterConfig {
  const LlmAdapterConfig({
    required this.apiKey,
    required this.model,
    required this.temperature,
    required this.maxRetries,
  });

  final String apiKey;
  final String model;
  final double temperature;

  /// `docs/specs/003-translation-engine.md` のリトライループが参照する値。
  /// 本仕様(002)のアダプター骨組み自体はリトライを行わない。
  final int maxRetries;
}
