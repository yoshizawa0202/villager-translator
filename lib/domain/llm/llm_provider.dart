/// サポートする LLM プロバイダー。
///
/// 識別子は `openai` / `anthropic` / `gemini` / `deepseek` / `qwen` / `kimi` の
/// 6種類のみとし、旧実装に存在した `"google"` という識別子は使用しない
/// (`docs/specs/010-additional-llm-providers.md` §5)。
///
/// [id] はセキュアストレージの API キーのキー名にも使うため、プロバイダーごとに
/// 一意でなければならない(010 AC-03: API キーの独立保存)。
enum LlmProvider {
  openai('openai', 'OpenAI'),
  anthropic('anthropic', 'Anthropic'),
  gemini('gemini', 'Google Gemini'),
  deepseek('deepseek', 'DeepSeek'),
  qwen('qwen', 'Qwen'),
  kimi('kimi', 'Kimi');

  const LlmProvider(this.id, this.displayName);

  /// 設定ファイル・セキュアストレージのキー・アダプター選択で使う識別子。
  final String id;

  /// UI に表示する名称。
  final String displayName;

  /// [id] から [LlmProvider] を解決する。未知の識別子は例外を投げる。
  static LlmProvider fromId(String id) {
    for (final provider in LlmProvider.values) {
      if (provider.id == id) {
        return provider;
      }
    }
    throw ArgumentError.value(id, 'id', '未知のプロバイダー識別子です');
  }
}
