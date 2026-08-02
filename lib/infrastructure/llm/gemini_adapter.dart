import '../../domain/llm/default_prompts.dart';
import '../../domain/llm/llm_adapter.dart';
import '../../domain/llm/llm_adapter_config.dart';
import '../../domain/llm/llm_provider.dart';
import '../../domain/llm/prompt_formatter.dart';
import '../../domain/llm/response_parser.dart';
import 'http_llm_adapter_base.dart';

/// Google Gemini `generateContent` API 向けアダプター(feature-spec.md §5.1)。
///
/// 内部識別子は仕様どおり `gemini` に統一する(`"google"` は使用しない)。
class GeminiAdapter extends HttpLlmAdapterBase implements LlmAdapter {
  GeminiAdapter(this.config, {super.client});

  final LlmAdapterConfig config;

  static const String _baseUrl =
      'https://generativelanguage.googleapis.com/v1beta';

  @override
  LlmProvider get provider => LlmProvider.gemini;

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
      Uri.parse(
        '$_baseUrl/models/${config.model}:generateContent?key=${config.apiKey}',
      ),
      headers: const {},
      body: {
        'system_instruction': {
          'parts': [
            {'text': systemPrompt},
          ],
        },
        'contents': [
          {
            'role': 'user',
            'parts': [
              {'text': userPrompt},
            ],
          },
        ],
        'generationConfig': {'temperature': config.temperature},
      },
    );

    final text = json['candidates'][0]['content']['parts'][0]['text'] as String;
    return parseTranslationResponse(text, content.keys.toList());
  }

  @override
  Future<bool> validateApiKey(String apiKey) {
    return getOk(Uri.parse('$_baseUrl/models?key=$apiKey'), headers: const {});
  }
}
