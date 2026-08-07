import '../../domain/llm/default_prompts.dart';
import '../../domain/llm/llm_adapter.dart';
import '../../domain/llm/llm_adapter_config.dart';
import '../../domain/llm/llm_provider.dart';
import '../../domain/llm/prompt_formatter.dart';
import '../../domain/llm/response_parser.dart';
import '../../domain/llm/thinking_level.dart';
import 'http_llm_adapter_base.dart';

/// Anthropic Messages API 向けアダプター(feature-spec.md §5.1)。
class AnthropicAdapter extends HttpLlmAdapterBase implements LlmAdapter {
  AnthropicAdapter(this.config, {super.client});

  final LlmAdapterConfig config;

  static const String _baseUrl = 'https://api.anthropic.com/v1';
  static const String _apiVersion = '2023-06-01';

  /// 翻訳応答として許容する最大出力トークン数。
  static const int maxOutputTokens = 4096;

  /// 思考量レベルごとの `thinking.budget_tokens`。
  /// いずれも [maxOutputTokens] 未満(Anthropic API の `budget_tokens < max_tokens`
  /// 制約を満たすため、`docs/specs/009-thinking-level-setting.md`)。
  static const Map<ThinkingLevel, int> _thinkingBudgetTokens = {
    ThinkingLevel.low: 1024,
    ThinkingLevel.medium: 2048,
    ThinkingLevel.high: 3072,
  };

  @override
  LlmProvider get provider => LlmProvider.anthropic;

  Map<String, String> _authHeaders(String apiKey) => {
    'x-api-key': apiKey,
    'anthropic-version': _apiVersion,
  };

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
      Uri.parse('$_baseUrl/messages'),
      headers: _authHeaders(config.apiKey),
      body: {
        'model': config.model,
        'max_tokens': maxOutputTokens,
        'temperature': config.temperature,
        'system': systemPrompt,
        if (_thinkingParamFor(config.thinkingLevel) != null)
          'thinking': _thinkingParamFor(config.thinkingLevel),
        'messages': [
          {'role': 'user', 'content': userPrompt},
        ],
      },
    );

    final blocks = json['content'] as List<dynamic>;
    final text = blocks
        .where((block) => block['type'] == 'text')
        .map((block) => block['text'] as String)
        .join();
    return parseTranslationResponse(text, content.keys.toList());
  }

  @override
  Future<bool> validateApiKey(String apiKey) {
    return getOk(Uri.parse('$_baseUrl/models'), headers: _authHeaders(apiKey));
  }

  /// [level] を Anthropic の `thinking` フィールドへ変換する。`off` は `null`
  /// (フィールド自体を省略することを表す、`docs/specs/009-thinking-level-setting.md`)。
  Map<String, dynamic>? _thinkingParamFor(ThinkingLevel level) {
    final budgetTokens = _thinkingBudgetTokens[level];
    if (budgetTokens == null) return null;
    return {'type': 'enabled', 'budget_tokens': budgetTokens};
  }
}
