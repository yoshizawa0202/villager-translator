/// 思考量(reasoning effort / extended thinking)の抽象レベル
/// (`docs/specs/009-thinking-level-setting.md`、`docs/specs/010-additional-llm-providers.md`)。
///
/// OpenAI の `reasoning_effort`、Anthropic の `thinking.budget_tokens`、
/// Gemini の `thinkingConfig.thinkingBudget` / `thinkingConfig.thinkingLevel`、
/// Qwen の `enable_thinking` はパラメータ形式・対応モデルがプロバイダーごとに
/// 異なるため、UI・設定ファイルではこの抽象レベルのみを扱い、実際の API
/// パラメータへの変換は各アダプターの責務とする。
///
/// どのレベルをモデルごとに提示するかは [ThinkingLevel] 自身ではなく
/// `model_catalog.dart` の `ModelCapabilities` が唯一の判断元となる
/// (010 §6.2、§14.1)。
enum ThinkingLevel {
  off('off', 'OFF'),
  on('on', 'ON'),
  low('low', '低'),
  medium('medium', '中'),
  high('high', '高'),
  max('max', '最大');

  const ThinkingLevel(this.id, this.displayName);

  /// 設定ファイルに保存する識別子。
  final String id;

  /// UI に表示する名称。
  final String displayName;

  /// [id] から [ThinkingLevel] を解決する。未知の識別子は例外を投げる。
  static ThinkingLevel fromId(String id) {
    for (final level in ThinkingLevel.values) {
      if (level.id == id) {
        return level;
      }
    }
    throw ArgumentError.value(id, 'id', '未知の思考量レベル識別子です');
  }
}
