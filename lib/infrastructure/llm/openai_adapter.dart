import '../../domain/llm/llm_provider.dart';
import '../../domain/llm/thinking_level.dart';
import 'openai_compatible_adapter_base.dart';

/// OpenAI Chat Completions API 向けアダプター(feature-spec.md §5.1)。
class OpenAiAdapter extends OpenAiCompatibleAdapterBase {
  OpenAiAdapter(super.config, {super.client});

  @override
  LlmProvider get provider => LlmProvider.openai;

  @override
  String get defaultBaseUrl => 'https://api.openai.com/v1';

  /// [level] を OpenAI の `reasoning_effort` へ変換する。`off` はパラメータ
  /// 自体を送信しない(`docs/specs/009-thinking-level-setting.md`)。
  ///
  /// `on` / `max` は OpenAI モデルのカタログでは選択肢に出ないが、カスタムモデル
  /// 経由で渡された場合に備えて安全な値へ丸める(010 §6.3 と同じ防御方針)。
  @override
  Map<String, dynamic> thinkingParameters(ThinkingLevel level) {
    switch (level) {
      case ThinkingLevel.off:
        return const {};
      case ThinkingLevel.low:
        return const {'reasoning_effort': 'low'};
      case ThinkingLevel.on:
      case ThinkingLevel.medium:
        return const {'reasoning_effort': 'medium'};
      case ThinkingLevel.high:
      case ThinkingLevel.max:
        return const {'reasoning_effort': 'high'};
    }
  }
}
