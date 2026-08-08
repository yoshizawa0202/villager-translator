import 'llm_provider.dart';
import 'thinking_level.dart';

/// モデル1件分のメタ情報。
///
/// [supportedThinkingLevels] は選択可能な [ThinkingLevel] の一覧で、
/// 必ず [ThinkingLevel.off] を含む。`off` のみの場合は思考量設定に
/// 対応していないモデルであることを表す(`docs/specs/009-thinking-level-setting.md`)。
class ModelInfo {
  const ModelInfo({
    required this.id,
    this.supportedThinkingLevels = const [ThinkingLevel.off],
  });

  final String id;
  final List<ThinkingLevel> supportedThinkingLevels;

  /// `off` 以外の思考量レベルに対応しているかどうか。
  bool get supportsThinking =>
      supportedThinkingLevels.any((level) => level != ThinkingLevel.off);
}

/// 思考量対応レベル。可読性のための省略表記。
const List<ThinkingLevel> _kFullThinking = [
  ThinkingLevel.off,
  ThinkingLevel.low,
  ThinkingLevel.medium,
  ThinkingLevel.high,
];
const List<ThinkingLevel> _kPartialThinking = [
  ThinkingLevel.off,
  ThinkingLevel.low,
  ThinkingLevel.medium,
];

/// プロバイダーごとに UI で選択肢として提示する代表的なモデル名と、
/// モデルごとの思考量対応可否。
///
/// 一覧にないモデルを使いたい場合は「カスタム」を選び自由入力にフォールバックする
/// (feature-spec.md §4.1)。新モデルのリリースや思考量対応状況の変化に合わせて
/// 更新する保守対象(`docs/specs/009-thinking-level-setting.md`)。
const Map<LlmProvider, List<ModelInfo>> kModelCatalog = {
  LlmProvider.openai: [
    ModelInfo(id: 'gpt-5.4-nano'), // 軽量、reasoning 非対応
    ModelInfo(
      id: 'gpt-5.6-luna',
      supportedThinkingLevels: _kFullThinking,
    ), // 軽量
    ModelInfo(id: 'gpt-5.4-mini'), // 軽量、reasoning 非対応
    ModelInfo(
      id: 'gpt-5.4',
      supportedThinkingLevels: _kFullThinking,
    ), // バランス(旧世代・低コスト)
    ModelInfo(
      id: 'gpt-5.6-terra',
      supportedThinkingLevels: _kFullThinking,
    ), // バランス
    ModelInfo(
      id: 'gpt-5.6-sol',
      supportedThinkingLevels: _kFullThinking,
    ), // フラッグシップ
  ],
  LlmProvider.anthropic: [
    ModelInfo(
      id: 'claude-haiku-4-5',
      supportedThinkingLevels: _kPartialThinking,
    ), // 軽量
    ModelInfo(
      id: 'claude-sonnet-5',
      supportedThinkingLevels: _kFullThinking,
    ), // バランス
    ModelInfo(
      id: 'claude-opus-5',
      supportedThinkingLevels: _kFullThinking,
    ), // フラッグシップ
  ],
  LlmProvider.gemini: [
    ModelInfo(id: 'gemini-3.1-flash-lite'), // 軽量、thinking 非対応
    ModelInfo(id: 'gemini-3.5-flash-lite'), // 軽量、thinking 非対応
    ModelInfo(
      id: 'gemini-3.5-flash',
      supportedThinkingLevels: _kFullThinking,
    ), // バランス
    ModelInfo(
      id: 'gemini-3.6-flash',
      supportedThinkingLevels: _kFullThinking,
    ), // バランス
    ModelInfo(
      id: 'gemini-3.1-pro-preview',
      supportedThinkingLevels: _kFullThinking,
    ), // フラッグシップ
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

/// [provider] の [kModelCatalog] から [modelId] に一致する [ModelInfo] を返す。
/// 一覧に存在しない場合(カスタムモデル・未知のモデル)は `null` を返す。
ModelInfo? modelInfoFor(LlmProvider provider, String modelId) {
  final models = kModelCatalog[provider] ?? const [];
  for (final info in models) {
    if (info.id == modelId) {
      return info;
    }
  }
  return null;
}
