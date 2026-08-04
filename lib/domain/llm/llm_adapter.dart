import 'default_prompts.dart';
import 'llm_provider.dart';

/// LLM 翻訳サービスの共通インターフェース(feature-spec.md §5.1)。
///
/// 差し替え可能なアダプター境界として、MOD/クエスト/Patchouli/カスタムファイル
/// 翻訳などの上位機能はこのインターフェースのみに依存する(AGENTS.md のドメイン
/// 上の制約)。
abstract class LlmAdapter {
  /// このアダプターが対応するプロバイダー。
  LlmProvider get provider;

  /// [content] を [targetLanguage] へ翻訳する。
  ///
  /// 戻り値の Map は [content] と同じキー集合を持つ。キー数が一致しない場合は
  /// [FormatException] を投げる。チャンク分割・リトライは呼び出し側
  /// (`docs/specs/003-translation-engine.md`)の責務であり、本メソッドは
  /// 1回の LLM 呼び出しのみを行う。
  Future<Map<String, String>> translate({
    required Map<String, String> content,
    required String targetLanguage,
    String systemPrompt = kDefaultSystemPrompt,
    String userPromptTemplate = kDefaultUserPrompt,
  });

  /// 設定画面での疎通確認用に、軽量な API 呼び出しで [apiKey] の有効性を検証する。
  Future<bool> validateApiKey(String apiKey);
}
