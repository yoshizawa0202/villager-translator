import '../../domain/llm/llm_api_exception.dart';
import '../../domain/llm/llm_provider.dart';
import '../../domain/llm/thinking_level.dart';
import 'openai_compatible_adapter_base.dart';

/// Qwen(DashScope の OpenAI 互換モード)向けアダプター
/// (`docs/specs/010-additional-llm-providers.md` §5.1、§9、§10)。
class QwenAdapter extends OpenAiCompatibleAdapterBase {
  QwenAdapter(super.config, {super.client});

  /// 既定の国際向けエンドポイント。設定画面の「Qwen API ベース URL(任意)」で
  /// 上書きできる(010 §9)。
  static const String internationalBaseUrl =
      'https://dashscope-intl.aliyuncs.com/compatible-mode/v1';

  /// 疎通確認で使う最小生成トークン数(010 §10)。
  static const int connectionCheckMaxTokens = 1;

  @override
  LlmProvider get provider => LlmProvider.qwen;

  @override
  String get defaultBaseUrl => internationalBaseUrl;

  /// Qwen は思考量を段階値ではなく `enable_thinking` の ON/OFF で扱う
  /// (010 §5.1: 選択肢は OFF / ON)。
  ///
  /// カスタムモデル経由で段階値が渡された場合は、`off` 以外をすべて ON とみなす。
  @override
  Map<String, dynamic> thinkingParameters(ThinkingLevel level) => {
    'enable_thinking': level != ThinkingLevel.off,
  };

  /// 疎通確認は Chat Completion への最小リクエストを1回だけ送る(010 §14.5)。
  ///
  /// 互換モードのモデル一覧取得 API を公式資料で確認できないため、実際の翻訳
  /// 経路に近い Chat Completion を使い、API キー・ベース URL・モデル利用可否を
  /// 同時に確認する。生成量は [connectionCheckMaxTokens] に制限し、不要な複数
  /// リクエストは送らない。
  @override
  Future<bool> validateApiKey(String apiKey) async {
    try {
      await postJson(
        Uri.parse('$baseUrl/chat/completions'),
        headers: authHeadersFor(apiKey),
        body: {
          'model': config.model,
          'max_tokens': connectionCheckMaxTokens,
          ...thinkingParameters(ThinkingLevel.off),
          'messages': [
            {'role': 'user', 'content': 'ping'},
          ],
        },
      );
      return true;
    } on LlmApiException catch (error) {
      // HTTP エラーは「疎通できなかった」として false を返す。タイムアウトや
      // ネットワーク障害(statusCode が無いもの)は、利用者向けメッセージを
      // 保つために呼び出し元へそのまま伝える。
      if (error.statusCode == null) rethrow;
      return false;
    }
  }
}
