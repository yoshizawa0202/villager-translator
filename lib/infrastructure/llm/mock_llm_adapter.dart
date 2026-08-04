import '../../domain/llm/default_prompts.dart';
import '../../domain/llm/llm_adapter.dart';
import '../../domain/llm/llm_provider.dart';

/// テスト・UI 疎通確認用の固定文字列を返すアダプター(feature-spec.md §5.1)。
///
/// ネットワーク呼び出しを一切行わない。
class MockLlmAdapter implements LlmAdapter {
  const MockLlmAdapter();

  @override
  LlmProvider get provider => LlmProvider.openai;

  @override
  Future<Map<String, String>> translate({
    required Map<String, String> content,
    required String targetLanguage,
    String systemPrompt = kDefaultSystemPrompt,
    String userPromptTemplate = kDefaultUserPrompt,
  }) async {
    return {
      for (final entry in content.entries) entry.key: '[MOCK] ${entry.value}',
    };
  }

  @override
  Future<bool> validateApiKey(String apiKey) async {
    return apiKey.trim().isNotEmpty;
  }
}
