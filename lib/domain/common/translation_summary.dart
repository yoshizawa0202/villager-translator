/// 翻訳対象の種別(MOD / クエスト / Patchouli ガイドブック / カスタムファイル)。
enum TranslationTargetType {
  mod,
  quest,
  patchouli,
  custom;

  static TranslationTargetType? fromName(String? name) {
    for (final value in TranslationTargetType.values) {
      if (value.name == name) return value;
    }
    return null;
  }
}

/// 翻訳履歴・完了サマリに表示する対象1件分の結果
/// (feature-spec.md §2 の `TranslationResult` 形状 + 008 の必須フィールド)。
class TranslationSummaryItem {
  const TranslationSummaryItem({
    required this.type,
    required this.id,
    this.displayName,
    required this.targetLanguage,
    this.outputPath,
    required this.success,
    required this.translatedKeyCount,
    required this.totalKeyCount,
  });

  final TranslationTargetType type;
  final String id;
  final String? displayName;
  final String targetLanguage;
  final String? outputPath;
  final bool success;
  final int translatedKeyCount;
  final int totalKeyCount;

  Map<String, dynamic> toJson() => {
    'type': type.name,
    'id': id,
    'displayName': displayName,
    'targetLanguage': targetLanguage,
    'outputPath': outputPath,
    'success': success,
    'translatedKeyCount': translatedKeyCount,
    'totalKeyCount': totalKeyCount,
  };

  /// JSON から復元する。値が欠損・不正な場合は安全側(失敗扱い・0件)へ
  /// フォールバックする([AppSettings.fromJson] と同じ防御的な方針)。
  factory TranslationSummaryItem.fromJson(Map<String, dynamic> json) {
    return TranslationSummaryItem(
      type:
          TranslationTargetType.fromName(json['type'] as String?) ??
          TranslationTargetType.custom,
      id: json['id'] as String? ?? '',
      displayName: json['displayName'] as String?,
      targetLanguage: json['targetLanguage'] as String? ?? '',
      outputPath: json['outputPath'] as String?,
      success: json['success'] as bool? ?? false,
      translatedKeyCount: (json['translatedKeyCount'] as num?)?.toInt() ?? 0,
      totalKeyCount: (json['totalKeyCount'] as num?)?.toInt() ?? 0,
    );
  }
}

/// 1回の翻訳実行(セッション)の結果全体
/// (`translation_summary.json` の内容、feature-spec.md §13)。
class TranslationSummary {
  const TranslationSummary({
    required this.sessionId,
    required this.targetLanguage,
    required this.createdAt,
    required this.items,
  });

  final String sessionId;
  final String targetLanguage;
  final DateTime createdAt;
  final List<TranslationSummaryItem> items;

  int get successCount => items.where((i) => i.success).length;
  int get failureCount => items.where((i) => !i.success).length;
  int get totalCount => items.length;

  Map<String, dynamic> toJson() => {
    'sessionId': sessionId,
    'targetLanguage': targetLanguage,
    'createdAt': createdAt.toIso8601String(),
    'items': items.map((i) => i.toJson()).toList(),
  };

  factory TranslationSummary.fromJson(Map<String, dynamic> json) {
    final itemsJson = json['items'];
    return TranslationSummary(
      sessionId: json['sessionId'] as String? ?? '',
      targetLanguage: json['targetLanguage'] as String? ?? '',
      createdAt:
          DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      items: itemsJson is List
          ? itemsJson
                .whereType<Map<String, dynamic>>()
                .map(TranslationSummaryItem.fromJson)
                .toList()
          : const [],
    );
  }
}
