/// 思考量(reasoning effort / extended thinking)の抽象レベル(`docs/specs/009-thinking-level-setting.md`)。
///
/// OpenAI の `reasoning_effort`、Anthropic の `thinking.budget_tokens`、
/// Gemini の `thinkingConfig.thinkingBudget` はパラメータ形式・対応モデルが
/// プロバイダーごとに異なるため、UI・設定ファイルではこの抽象レベルのみを扱い、
/// 実際の API パラメータへの変換は各アダプターの責務とする。
enum ThinkingLevel {
  off('off', 'OFF'),
  low('low', '低'),
  medium('medium', '中'),
  high('high', '高');

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
