import '../../domain/llm/llm_provider.dart';
import '../../domain/llm/thinking_level.dart';
import 'openai_compatible_adapter_base.dart';

/// DeepSeek(OpenAI 互換 Chat Completions API)向けアダプター
/// (`docs/specs/010-additional-llm-providers.md` §5.1)。
///
/// 翻訳結果には `choices[0].message.content` のみを採用し、`reasoning_content`
/// は取り込まない(基底クラスの [OpenAiCompatibleAdapterBase.extractContent])。
class DeepSeekAdapter extends OpenAiCompatibleAdapterBase {
  DeepSeekAdapter(super.config, {super.client});

  @override
  LlmProvider get provider => LlmProvider.deepseek;

  @override
  String get defaultBaseUrl => 'https://api.deepseek.com/v1';

  /// [level] を DeepSeek の `reasoning_effort` へ変換する(010 §6.3)。
  ///
  /// 通常のモデル選択 UI では OFF / 高 / 最大しか提示しないが、カスタムモデル
  /// などを経由して `low` / `medium` が渡された場合は安全な値へ補正する。
  /// `medium` を `high` へ丸めるのは、API 側で高相当へ丸められる挙動との
  /// 互換性を確保するための防御処理。
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
