import 'existing_translation_policy.dart';
import 'supported_language.dart';

/// 翻訳の挙動に関する設定(feature-spec.md §4.2)。
class TranslationSettings {
  const TranslationSettings({
    required this.useTokenBasedChunking,
    required this.maxTokensPerChunk,
    required this.fallbackToEntryBased,
    required this.existingTranslationPolicy,
    required this.resourcePackName,
    required this.modChunkSize,
    required this.questChunkSize,
    required this.guidebookChunkSize,
    required this.customLanguages,
  });

  final bool useTokenBasedChunking;
  final int maxTokensPerChunk;
  final bool fallbackToEntryBased;
  final ExistingTranslationPolicy existingTranslationPolicy;
  final String resourcePackName;
  final int modChunkSize;
  final int questChunkSize;
  final int guidebookChunkSize;

  /// ユーザーが追加したカスタム言語(既定9言語は含まない)。
  final List<SupportedLanguage> customLanguages;

  /// 既定言語 + カスタム言語をまとめた、対象言語ダイアログに表示する全言語。
  List<SupportedLanguage> get allLanguages => [
    ...kDefaultLanguages,
    ...customLanguages,
  ];

  static TranslationSettings defaults() => const TranslationSettings(
    useTokenBasedChunking: false,
    maxTokensPerChunk: 3000,
    fallbackToEntryBased: true,
    existingTranslationPolicy: ExistingTranslationPolicy.diffUpdate,
    resourcePackName: 'VillagerTranslator',
    modChunkSize: 50,
    questChunkSize: 1,
    guidebookChunkSize: 1,
    customLanguages: [],
  );

  TranslationSettings copyWith({
    bool? useTokenBasedChunking,
    int? maxTokensPerChunk,
    bool? fallbackToEntryBased,
    ExistingTranslationPolicy? existingTranslationPolicy,
    String? resourcePackName,
    int? modChunkSize,
    int? questChunkSize,
    int? guidebookChunkSize,
    List<SupportedLanguage>? customLanguages,
  }) {
    return TranslationSettings(
      useTokenBasedChunking:
          useTokenBasedChunking ?? this.useTokenBasedChunking,
      maxTokensPerChunk: maxTokensPerChunk ?? this.maxTokensPerChunk,
      fallbackToEntryBased: fallbackToEntryBased ?? this.fallbackToEntryBased,
      existingTranslationPolicy:
          existingTranslationPolicy ?? this.existingTranslationPolicy,
      resourcePackName: resourcePackName ?? this.resourcePackName,
      modChunkSize: modChunkSize ?? this.modChunkSize,
      questChunkSize: questChunkSize ?? this.questChunkSize,
      guidebookChunkSize: guidebookChunkSize ?? this.guidebookChunkSize,
      customLanguages: customLanguages ?? this.customLanguages,
    );
  }

  Map<String, dynamic> toJson() => {
    'useTokenBasedChunking': useTokenBasedChunking,
    'maxTokensPerChunk': maxTokensPerChunk,
    'fallbackToEntryBased': fallbackToEntryBased,
    'existingTranslationPolicy': existingTranslationPolicy.toJsonValue(),
    'resourcePackName': resourcePackName,
    'modChunkSize': modChunkSize,
    'questChunkSize': questChunkSize,
    'guidebookChunkSize': guidebookChunkSize,
    'customLanguages': customLanguages.map((e) => e.toJson()).toList(),
  };

  factory TranslationSettings.fromJson(Map<String, dynamic> json) {
    final fallback = TranslationSettings.defaults();

    final rawLanguages = json['customLanguages'];
    final customLanguages = rawLanguages is List
        ? rawLanguages
              .whereType<Map<String, dynamic>>()
              .map(SupportedLanguage.fromJson)
              .toList()
        : fallback.customLanguages;

    return TranslationSettings(
      useTokenBasedChunking:
          json['useTokenBasedChunking'] as bool? ??
          fallback.useTokenBasedChunking,
      maxTokensPerChunk:
          (json['maxTokensPerChunk'] as num?)?.toInt() ??
          fallback.maxTokensPerChunk,
      fallbackToEntryBased:
          json['fallbackToEntryBased'] as bool? ??
          fallback.fallbackToEntryBased,
      existingTranslationPolicy: ExistingTranslationPolicy.fromJsonValue(
        json['existingTranslationPolicy'] as String?,
      ),
      resourcePackName:
          json['resourcePackName'] as String? ?? fallback.resourcePackName,
      modChunkSize:
          (json['modChunkSize'] as num?)?.toInt() ?? fallback.modChunkSize,
      questChunkSize:
          (json['questChunkSize'] as num?)?.toInt() ?? fallback.questChunkSize,
      guidebookChunkSize:
          (json['guidebookChunkSize'] as num?)?.toInt() ??
          fallback.guidebookChunkSize,
      customLanguages: customLanguages,
    );
  }
}
