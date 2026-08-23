import 'llm_provider.dart';
import 'thinking_level.dart';

/// モデル1件分の能力情報(`docs/specs/010-additional-llm-providers.md` §6.2)。
///
/// 設定 UI の選択肢・既定値・入力検証・アダプターへ渡す送信パラメーターは
/// すべてこの能力情報から導出する。モデルごとの条件分岐を UI・検証・アダプターへ
/// 分散させないための唯一の判断元(010 §14.1)。
class ModelCapabilities {
  const ModelCapabilities({
    required this.thinkingLevels,
    required this.defaultThinkingLevel,
    this.supportsTemperature = true,
  });

  /// このモデルで選択できる思考量。UI のコンボボックスはこの順序・この要素だけを
  /// 提示する(010 AC-06: 利用できない選択肢を表示しない)。
  ///
  /// [ThinkingLevel.off] を含まないモデル(Gemini 3.7 Flash、Kimi K3)は
  /// 思考を無効化できないことを表す。
  final List<ThinkingLevel> thinkingLevels;

  /// モデル選択時に採用する既定の思考量。必ず [thinkingLevels] に含まれる。
  final ThinkingLevel defaultThinkingLevel;

  /// `temperature` を送信してよいかどうか。`false` のモデルへは
  /// サンプリングパラメーターを一切送信しない(010 §8)。
  final bool supportsTemperature;

  /// 思考量を OFF にできるかどうか。[thinkingLevels] から導出することで、
  /// 選択肢一覧と OFF 対応可否が食い違わないようにする。
  bool get supportsThinkingOff => thinkingLevels.contains(ThinkingLevel.off);

  /// `off` 以外の思考量レベルに対応しているかどうか。
  bool get supportsThinking =>
      thinkingLevels.any((level) => level != ThinkingLevel.off);

  /// [level] をこのモデルで選択できるかどうか。
  bool supportsLevel(ThinkingLevel level) => thinkingLevels.contains(level);
}

/// 思考量に対応しないモデル。
const ModelCapabilities kNoThinking = ModelCapabilities(
  thinkingLevels: [ThinkingLevel.off],
  defaultThinkingLevel: ThinkingLevel.off,
);

/// OFF / 低 / 中 / 高(OpenAI・Anthropic・既存 Gemini の標準的な段階)。
const ModelCapabilities kOffLowMediumHigh = ModelCapabilities(
  thinkingLevels: [
    ThinkingLevel.off,
    ThinkingLevel.low,
    ThinkingLevel.medium,
    ThinkingLevel.high,
  ],
  defaultThinkingLevel: ThinkingLevel.off,
);

/// OFF / 低 / 中(高に対応しないモデル)。
const ModelCapabilities kOffLowMedium = ModelCapabilities(
  thinkingLevels: [ThinkingLevel.off, ThinkingLevel.low, ThinkingLevel.medium],
  defaultThinkingLevel: ThinkingLevel.off,
);

/// DeepSeek V4 系: OFF / 高 / 最大(010 §5.1)。
///
/// 「低」「中」は通常のモデル選択 UI では提示しない(010 §6.3、対象外)。
const ModelCapabilities kDeepSeekV4Thinking = ModelCapabilities(
  thinkingLevels: [ThinkingLevel.off, ThinkingLevel.high, ThinkingLevel.max],
  defaultThinkingLevel: ThinkingLevel.off,
);

/// Qwen3.8-Max: OFF / ON の2値(010 §5.1)。
const ModelCapabilities kQwenThinking = ModelCapabilities(
  thinkingLevels: [ThinkingLevel.off, ThinkingLevel.on],
  defaultThinkingLevel: ThinkingLevel.off,
);

/// Gemini 3.7 Flash: 低 / 中 / 高、既定は中。思考は無効化できず、
/// `temperature` を含むサンプリングパラメーターを送信しない(010 §8)。
const ModelCapabilities kGemini37FlashThinking = ModelCapabilities(
  thinkingLevels: [ThinkingLevel.low, ThinkingLevel.medium, ThinkingLevel.high],
  defaultThinkingLevel: ThinkingLevel.medium,
  supportsTemperature: false,
);

/// Kimi K3: 低 / 高 / 最大、既定は最大(010 §5.1)。思考は無効化できない。
const ModelCapabilities kKimiK3Thinking = ModelCapabilities(
  thinkingLevels: [ThinkingLevel.low, ThinkingLevel.high, ThinkingLevel.max],
  defaultThinkingLevel: ThinkingLevel.max,
);

/// カスタムモデル・カタログに存在しないモデル用の能力情報。
///
/// 対応可否が判断できないため制限せず、既存の挙動どおり `temperature` を送信し、
/// すべての思考量を選択できるものとして扱う。
const ModelCapabilities kUnknownModelCapabilities = ModelCapabilities(
  thinkingLevels: ThinkingLevel.values,
  defaultThinkingLevel: ThinkingLevel.off,
);

/// モデル1件分のメタ情報。
class ModelInfo {
  const ModelInfo({required this.id, this.capabilities = kNoThinking});

  final String id;

  /// このモデルの能力情報(010 §6.2)。
  final ModelCapabilities capabilities;

  /// 選択可能な思考量レベルの一覧([capabilities] の委譲)。
  List<ThinkingLevel> get supportedThinkingLevels =>
      capabilities.thinkingLevels;

  /// `off` 以外の思考量レベルに対応しているかどうか。
  bool get supportsThinking => capabilities.supportsThinking;
}

/// プロバイダーごとに UI で選択肢として提示するモデルと、その能力情報。
///
/// 一覧にないモデルを使いたい場合は「カスタム」を選び自由入力にフォールバックする
/// (feature-spec.md §4.1)。新モデルのリリースや思考量対応状況の変化に合わせて
/// 更新する保守対象(`docs/specs/009-thinking-level-setting.md`、
/// `docs/specs/010-additional-llm-providers.md`)。
const Map<LlmProvider, List<ModelInfo>> kModelCatalog = {
  LlmProvider.openai: [
    ModelInfo(id: 'gpt-5.4-nano'), // 軽量、reasoning 非対応
    ModelInfo(id: 'gpt-5.6-luna', capabilities: kOffLowMediumHigh), // 軽量
    ModelInfo(id: 'gpt-5.4-mini'), // 軽量、reasoning 非対応
    ModelInfo(id: 'gpt-5.4', capabilities: kOffLowMediumHigh), // バランス(旧世代・低コスト)
    ModelInfo(id: 'gpt-5.6-terra', capabilities: kOffLowMediumHigh), // バランス
    ModelInfo(id: 'gpt-5.6-sol', capabilities: kOffLowMediumHigh), // フラッグシップ
  ],
  LlmProvider.anthropic: [
    ModelInfo(id: 'claude-haiku-4-5', capabilities: kOffLowMedium), // 軽量
    ModelInfo(id: 'claude-sonnet-5', capabilities: kOffLowMediumHigh), // バランス
    ModelInfo(id: 'claude-opus-5', capabilities: kOffLowMediumHigh), // フラッグシップ
  ],
  LlmProvider.gemini: [
    ModelInfo(id: 'gemini-3.1-flash-lite'), // 軽量、thinking 非対応
    ModelInfo(id: 'gemini-3.5-flash-lite'), // 軽量、thinking 非対応
    ModelInfo(id: 'gemini-3.5-flash', capabilities: kOffLowMediumHigh), // バランス
    ModelInfo(id: 'gemini-3.6-flash', capabilities: kOffLowMediumHigh), // バランス
    ModelInfo(
      id: 'gemini-3.7-flash',
      capabilities: kGemini37FlashThinking,
    ), // バランス(thinkingLevel 方式)
    ModelInfo(
      id: 'gemini-3.1-pro-preview',
      capabilities: kOffLowMediumHigh,
    ), // フラッグシップ
  ],
  LlmProvider.deepseek: [
    ModelInfo(id: 'deepseek-v4-flash', capabilities: kDeepSeekV4Thinking), // 軽量
    ModelInfo(id: 'deepseek-v4-pro', capabilities: kDeepSeekV4Thinking), // 高性能
  ],
  LlmProvider.qwen: [ModelInfo(id: 'qwen3.8-max', capabilities: kQwenThinking)],
  LlmProvider.kimi: [ModelInfo(id: 'kimi-k3', capabilities: kKimiK3Thinking)],
};

/// プロバイダーごとの既定モデル。
const Map<LlmProvider, String> kDefaultModel = {
  LlmProvider.openai: 'gpt-5.6-luna',
  LlmProvider.anthropic: 'claude-haiku-4-5',
  LlmProvider.gemini: 'gemini-3.7-flash',
  LlmProvider.deepseek: 'deepseek-v4-flash',
  LlmProvider.qwen: 'qwen3.8-max',
  LlmProvider.kimi: 'kimi-k3',
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

/// [provider] の [modelId] の能力情報を返す。カタログに存在しないモデルには
/// [kUnknownModelCapabilities] を返し、判断できない項目で制限をかけない。
ModelCapabilities capabilitiesFor(LlmProvider provider, String modelId) {
  return modelInfoFor(provider, modelId)?.capabilities ??
      kUnknownModelCapabilities;
}
