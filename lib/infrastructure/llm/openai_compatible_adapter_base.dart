import '../../domain/llm/default_prompts.dart';
import '../../domain/llm/llm_adapter.dart';
import '../../domain/llm/llm_adapter_config.dart';
import '../../domain/llm/prompt_formatter.dart';
import '../../domain/llm/response_parser.dart';
import '../../domain/llm/thinking_level.dart';
import 'http_llm_adapter_base.dart';

/// OpenAI 互換 Chat Completions API を利用するアダプターの共通基底
/// (`docs/specs/010-additional-llm-providers.md` §7.1)。
///
/// OpenAI・DeepSeek・Qwen・Kimi はいずれも互換性の高い API 形式を使うため、
/// リクエスト組み立て・応答解釈・疎通確認の共通部分をここへ集約する。
/// 派生クラスの責務は原則として次の4点に限定する(010 AC-13)。
///
/// - ベース URL([defaultBaseUrl])
/// - 思考量のマッピング([thinkingParameters])
/// - サンプリングパラメーター([samplingParameters])
/// - 疎通確認方法([validateApiKey])
abstract class OpenAiCompatibleAdapterBase extends HttpLlmAdapterBase
    implements LlmAdapter {
  OpenAiCompatibleAdapterBase(this.config, {super.client});

  final LlmAdapterConfig config;

  /// 上書きが無い場合に使うベース URL(末尾に `/` を付けない)。
  String get defaultBaseUrl;

  /// 実際に使用するベース URL。[LlmAdapterConfig.baseUrl] の指定があれば
  /// そちらを優先する(010 §9)。
  String get baseUrl {
    final override = config.baseUrl?.trim();
    if (override == null || override.isEmpty) {
      return defaultBaseUrl;
    }
    return override.endsWith('/')
        ? override.substring(0, override.length - 1)
        : override;
  }

  /// Bearer 認証ヘッダー。API キーはログ・例外へ出力しない(010 §5.2)。
  Map<String, String> authHeadersFor(String apiKey) => {
    'Authorization': 'Bearer $apiKey',
  };

  /// 思考量をリクエストボディへ反映するパラメーター。
  /// 何も送信しない場合は空の Map を返す。
  Map<String, dynamic> thinkingParameters(ThinkingLevel level) => const {};

  /// サンプリングパラメーター。モデルが `temperature` 非対応であれば
  /// 何も送信しない(010 §6.2、モデル能力情報から導出する)。
  Map<String, dynamic> get samplingParameters =>
      config.capabilities.supportsTemperature
      ? {'temperature': config.temperature}
      : const {};

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
      Uri.parse('$baseUrl/chat/completions'),
      headers: authHeadersFor(config.apiKey),
      body: {
        'model': config.model,
        ...samplingParameters,
        ...thinkingParameters(config.thinkingLevel),
        'messages': [
          {'role': 'system', 'content': systemPrompt},
          {'role': 'user', 'content': userPrompt},
        ],
      },
    );

    return parseTranslationResponse(
      extractContent(json),
      content.keys.toList(),
    );
  }

  /// 翻訳結果として `choices[0].message.content` のみを採用する(010 §7.2)。
  ///
  /// DeepSeek 等が返す `reasoning_content`(内部推論)は利用者が求める翻訳本文
  /// ではなく、機密情報や不要な説明を含む可能性があるため連結しない(010 §14.4)。
  String extractContent(dynamic json) =>
      json['choices'][0]['message']['content'] as String;

  /// 既定の疎通確認はモデル一覧の取得。モデル一覧 API を公式に確認できない
  /// プロバイダー(Qwen)は派生クラスで上書きする(010 §10)。
  @override
  Future<bool> validateApiKey(String apiKey) {
    return getOk(Uri.parse('$baseUrl/models'), headers: authHeadersFor(apiKey));
  }
}
