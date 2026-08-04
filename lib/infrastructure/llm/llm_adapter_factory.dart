import 'package:http/http.dart' as http;

import '../../domain/llm/llm_adapter.dart';
import '../../domain/llm/llm_adapter_config.dart';
import '../../domain/llm/llm_provider.dart';
import 'anthropic_adapter.dart';
import 'gemini_adapter.dart';
import 'openai_adapter.dart';

/// [LlmProvider] から対応する [LlmAdapter] を生成する境界(feature-spec.md §5.1)。
abstract class LlmAdapterFactory {
  LlmAdapter create(LlmProvider provider, LlmAdapterConfig config);
}

/// 実プロバイダーアダプターを生成する既定実装。
///
/// `switch` はすべての [LlmProvider] を網羅しなければコンパイルエラーになるため、
/// 存在しない `"google"` のようなケースを追加してしまう心配がない(受け入れ条件12)。
class DefaultLlmAdapterFactory implements LlmAdapterFactory {
  DefaultLlmAdapterFactory({http.Client? client}) : _client = client;

  final http.Client? _client;

  @override
  LlmAdapter create(LlmProvider provider, LlmAdapterConfig config) {
    switch (provider) {
      case LlmProvider.openai:
        return OpenAiAdapter(config, client: _client);
      case LlmProvider.anthropic:
        return AnthropicAdapter(config, client: _client);
      case LlmProvider.gemini:
        return GeminiAdapter(config, client: _client);
    }
  }
}
