import '../../domain/llm/llm_provider.dart';
import '../../domain/llm/thinking_level.dart';
import 'openai_compatible_adapter_base.dart';

/// Kimi(Moonshot AI、OpenAI 互換 Chat Completions API)向けアダプター
/// (`docs/specs/010-additional-llm-providers.md` §5.1)。
class KimiAdapter extends OpenAiCompatibleAdapterBase {
  KimiAdapter(super.config, {super.client});

  @override
  LlmProvider get provider => LlmProvider.kimi;

  @override
  String get defaultBaseUrl => 'https://api.moonshot.ai/v1';

  /// [level] を Kimi の `reasoning_effort` へ変換する。
  ///
  /// Kimi K3 の選択肢は 低 / 高 / 最大 で、思考の無効化には対応しない
  /// (010 §5.1)。`off` / `on` / `medium` はカタログ外の経路でのみ渡りうるため、
  /// 対応する安全な値へ補正する。
  @override
  Map<String, dynamic> thinkingParameters(ThinkingLevel level) {
    switch (level) {
      case ThinkingLevel.off:
        return const {};
      case ThinkingLevel.low:
        return const {'reasoning_effort': 'low'};
      case ThinkingLevel.on:
      case ThinkingLevel.medium:
      case ThinkingLevel.high:
        return const {'reasoning_effort': 'high'};
      case ThinkingLevel.max:
        return const {'reasoning_effort': 'max'};
    }
  }
}
