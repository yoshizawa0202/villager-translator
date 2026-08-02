import '../../domain/llm/default_prompts.dart';
import '../../domain/llm/llm_adapter.dart';
import '../../domain/llm/llm_adapter_config.dart';
import '../../domain/llm/llm_provider.dart';
import '../../domain/llm/prompt_formatter.dart';
import '../../domain/llm/response_parser.dart';
import 'http_llm_adapter_base.dart';

/// OpenAI Chat Completions API 向けアダプター(feature-spec.md §5.1)。
class OpenAiAdapter extends HttpLlmAdapterBase implements LlmAdapter {
  OpenAiAdapter(this.config, {super.client});

  final LlmAdapterConfig config;

  static const String _baseUrl = 'https://api.openai.com/v1';

  @override
  LlmProvider get provider => LlmProvider.openai;

  @override
  Future<Map<String, String>> translate({
    required Map<String, String> content,
    required String targetLanguage,
    String systemPrompt = kDefaultSystemPrompt,
    String userPromptTemplate = kDefaultUserPrompt,
  }) async {
    final userPrompt = formatUserPrompt(
      userPromptTemplate,
      content: content,
      targetLanguage: targetLanguage,
    );

    final json = await postJson(
      Uri.parse('$_baseUrl/chat/completions'),
      headers: {'Authorization': 'Bearer ${config.apiKey}'},
      body: {
        'model': config.model,
        'temperature': config.temperature,
        'messages': [
          {'role': 'system', 'content': systemPrompt},
          {'role': 'user', 'content': userPrompt},
        ],
      },
    );

    final text = json['choices'][0]['message']['content'] as String;
    return parseTranslationResponse(text, content.keys.toList());
  }

  @override
  Future<bool> validateApiKey(String apiKey) {
    return getOk(
      Uri.parse('$_baseUrl/models'),
      headers: {'Authorization': 'Bearer $apiKey'},
    );
  }
}
