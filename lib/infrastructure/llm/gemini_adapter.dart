import '../../domain/llm/default_prompts.dart';
import '../../domain/llm/llm_adapter.dart';
import '../../domain/llm/llm_adapter_config.dart';
import '../../domain/llm/llm_provider.dart';
import '../../domain/llm/prompt_formatter.dart';
import '../../domain/llm/response_parser.dart';
import '../../domain/llm/thinking_level.dart';
import 'http_llm_adapter_base.dart';

/// Google Gemini `generateContent` API 向けアダプター(feature-spec.md §5.1)。
///
/// 内部識別子は仕様どおり `gemini` に統一する(`"google"` は使用しない)。
///
/// 思考量の送信方式はモデルによって2通りに分かれる
/// (`docs/specs/010-additional-llm-providers.md` §8、§14.3)。
///
/// - [thinkingLevelModels]: `thinkingConfig.thinkingLevel` を送信し、
///   `thinkingBudget` / `temperature` / `topP` / `topK` / `candidateCount` を
///   一切送信しない。
/// - それ以外(Gemini 3.6 以前を含む既存モデル): 従来どおり
///   `thinkingConfig.thinkingBudget` と `temperature` を使う(後方互換)。
class GeminiAdapter extends HttpLlmAdapterBase implements LlmAdapter {
  GeminiAdapter(this.config, {super.client});

  final LlmAdapterConfig config;

  static const String _baseUrl =
      'https://generativelanguage.googleapis.com/v1beta';

  /// `thinkingConfig.thinkingLevel` 方式を使うモデル(010 §8)。
  /// 既存モデルを一律にこの方式へ移行することは本仕様の対象外。
  static const Set<String> thinkingLevelModels = {'gemini-3.7-flash'};

  /// 思考量レベルごとの `thinkingConfig.thinkingBudget`(既存モデル用、
  /// `docs/specs/009-thinking-level-setting.md`)。
  ///
  /// `on` / `max` は既存 Gemini モデルのカタログでは選択肢に出ないが、カスタム
  /// モデル経由で渡された場合に備えて近い段階へ割り当てる。
  static const Map<ThinkingLevel, int> _thinkingBudgets = {
    ThinkingLevel.low: 1024,
    ThinkingLevel.on: 8192,
    ThinkingLevel.medium: 8192,
    ThinkingLevel.high: 24576,
    ThinkingLevel.max: 24576,
  };

  /// 思考量レベルごとの `thinkingConfig.thinkingLevel`(010 §8)。
  static const Map<ThinkingLevel, String> _thinkingLevels = {
    ThinkingLevel.low: 'low',
    ThinkingLevel.on: 'medium',
    ThinkingLevel.medium: 'medium',
    ThinkingLevel.high: 'high',
    ThinkingLevel.max: 'high',
  };

  @override
  LlmProvider get provider => LlmProvider.gemini;

  /// このモデルが `thinkingLevel` 方式かどうか。
  bool get usesThinkingLevel => thinkingLevelModels.contains(config.model);

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

    final generationConfig = _buildGenerationConfig();

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
        if (generationConfig.isNotEmpty) 'generationConfig': generationConfig,
      },
    );

    final text = json['candidates'][0]['content']['parts'][0]['text'] as String;
    return parseTranslationResponse(text, content.keys.toList());
  }

  /// `generationConfig` を組み立てる。
  ///
  /// `temperature` の送信可否はモデル能力情報から導出し、アダプター側で
  /// モデル ID を条件分岐しない(010 §6.2、§14.1)。
  Map<String, dynamic> _buildGenerationConfig() {
    if (usesThinkingLevel) {
      final level = _thinkingLevels[config.thinkingLevel];
      return {
        if (level != null) 'thinkingConfig': {'thinkingLevel': level},
      };
    }

    final budget = _thinkingBudgets[config.thinkingLevel];
    return {
      if (config.capabilities.supportsTemperature)
        'temperature': config.temperature,
      if (budget != null) 'thinkingConfig': {'thinkingBudget': budget},
    };
  }

  @override
  Future<bool> validateApiKey(String apiKey) {
    return getOk(Uri.parse('$_baseUrl/models?key=$apiKey'), headers: const {});
  }
}
