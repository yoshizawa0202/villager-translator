import '../llm/llm_provider.dart';
import '../llm/model_catalog.dart';
import '../llm/thinking_level.dart';
import 'supported_language.dart';

/// 設定値の検証ロジック。
///
/// いずれの関数も `null` を返せば有効、それ以外は日本語のエラーメッセージを
/// 返す純粋関数。UI の `validator` コールバックと [SettingsController] の両方から
/// 共通で利用し、不正な値が保存されることを防ぐ(受け入れ条件3)。
class SettingsValidator {
  const SettingsValidator._();

  static const double minTemperature = 0.0;
  static const double maxTemperature = 2.0;
  static const int minMaxRetries = 0;
  static const int maxMaxRetries = 10;
  static const int minMaxTokensPerChunk = 1000;
  static const int maxMaxTokensPerChunk = 10000;
  static const int minChunkSize = 1;
  static const int maxChunkSize = 1000;

  static String? validateTemperature(double value) {
    if (value < minTemperature || value > maxTemperature) {
      return 'temperature は $minTemperature〜$maxTemperature の範囲で指定してください';
    }
    return null;
  }

  static String? validateMaxRetries(int value) {
    if (value < minMaxRetries || value > maxMaxRetries) {
      return '最大リトライ回数は $minMaxRetries〜$maxMaxRetries の範囲で指定してください';
    }
    return null;
  }

  static String? validateMaxTokensPerChunk(int value) {
    if (value < minMaxTokensPerChunk || value > maxMaxTokensPerChunk) {
      return 'チャンクあたり最大トークン数は $minMaxTokensPerChunk〜$maxMaxTokensPerChunk の範囲で指定してください';
    }
    return null;
  }

  static String? validateChunkSize(int value) {
    if (value < minChunkSize || value > maxChunkSize) {
      return 'チャンクサイズは $minChunkSize〜$maxChunkSize の範囲で指定してください';
    }
    return null;
  }

  /// [model] が「カスタム」選択の場合のみ [customModel] の非空を検証する。
  static String? validateCustomModel(String model, String customModel) {
    if (model == kCustomModelSentinel && customModel.trim().isEmpty) {
      return 'カスタムモデル名を入力してください';
    }
    return null;
  }

  /// 選択中の [model] が [thinkingLevel] に対応しているかを検証する
  /// (`docs/specs/009-thinking-level-setting.md`)。
  ///
  /// `off` は常に有効。「カスタム」選択時、および [kModelCatalog] に存在しない
  /// モデル ID の場合は対応可否が不明なため制限しない。
  static String? validateThinkingLevel(
    LlmProvider provider,
    String model,
    ThinkingLevel thinkingLevel,
  ) {
    if (thinkingLevel == ThinkingLevel.off) return null;
    if (model == kCustomModelSentinel) return null;

    final info = modelInfoFor(provider, model);
    if (info == null) return null;

    if (!info.supportedThinkingLevels.contains(thinkingLevel)) {
      return 'このモデルは選択した思考量に対応していません';
    }
    return null;
  }

  /// カスタム言語の追加時に、ID・表示名の非空と、既存言語(既定+カスタム)との
  /// 重複(大文字小文字を無視)がないことを検証する。
  static String? validateCustomLanguage(
    String id,
    String displayName,
    List<SupportedLanguage> existing,
  ) {
    final trimmedId = id.trim();
    final trimmedName = displayName.trim();

    if (trimmedId.isEmpty) {
      return '言語 ID を入力してください';
    }
    if (trimmedName.isEmpty) {
      return '表示名を入力してください';
    }

    final normalizedId = trimmedId.toLowerCase();
    final isDuplicate = existing.any(
      (lang) => lang.id.toLowerCase() == normalizedId,
    );
    if (isDuplicate) {
      return '同じ言語 ID が既に存在します';
    }

    return null;
  }
}
