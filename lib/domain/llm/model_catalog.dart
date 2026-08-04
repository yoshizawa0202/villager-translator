import 'llm_provider.dart';

/// プロバイダーごとに UI で選択肢として提示する代表的なモデル名。
///
/// 一覧にないモデルを使いたい場合は「カスタム」を選び自由入力にフォールバックする
/// (feature-spec.md §4.1)。新モデルのリリースに合わせて更新する保守対象。
const Map<LlmProvider, List<String>> kModelCatalog = {
  LlmProvider.openai: [
    'gpt-5.4-nano', // 軽量
    'gpt-5.6-luna', // 軽量
    'gpt-5.4-mini', // 軽量
    'gpt-5.4', // バランス(旧世代・低コスト)
    'gpt-5.6-terra', // バランス
    'gpt-5.6-sol', // フラッグシップ
  ],
  LlmProvider.anthropic: [
    'claude-haiku-4-5', // 軽量
    'claude-sonnet-5', // バランス
    'claude-opus-5', // フラッグシップ
  ],
  LlmProvider.gemini: [
    'gemini-3.1-flash-lite', // 軽量
    'gemini-3.5-flash-lite', // 軽量
    'gemini-3.5-flash', // バランス
    'gemini-3.6-flash', // バランス
    'gemini-3.1-pro-preview', // フラッグシップ
  ],
};

/// プロバイダーごとの既定モデル。
const Map<LlmProvider, String> kDefaultModel = {
  LlmProvider.openai: 'gpt-5.6-luna',
  LlmProvider.anthropic: 'claude-haiku-4-5',
  LlmProvider.gemini: 'gemini-3.5-flash-lite',
};

/// モデル選択コンボボックスで「カスタム」を表す番兵値。
const String kCustomModelSentinel = 'custom';
