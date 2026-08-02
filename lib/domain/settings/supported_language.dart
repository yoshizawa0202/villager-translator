/// 翻訳対象言語の定義(feature-spec.md §3.3)。
class SupportedLanguage {
  const SupportedLanguage({
    required this.id,
    required this.displayName,
    required this.isDefault,
  });

  /// Minecraft の言語コード(例: `ja_jp`)。
  final String id;

  /// UI に表示する名称。
  final String displayName;

  /// 既定9言語であれば true。既定言語は削除できない。
  final bool isDefault;

  factory SupportedLanguage.fromJson(Map<String, dynamic> json) {
    return SupportedLanguage(
      id: json['id'] as String,
      displayName: json['displayName'] as String,
      isDefault: false,
    );
  }

  Map<String, dynamic> toJson() => {'id': id, 'displayName': displayName};

  @override
  bool operator ==(Object other) =>
      other is SupportedLanguage &&
      other.id == id &&
      other.displayName == displayName;

  @override
  int get hashCode => Object.hash(id, displayName);
}

/// 削除不可の既定9言語(feature-spec.md §3.3)。
const List<SupportedLanguage> kDefaultLanguages = [
  SupportedLanguage(id: 'ja_jp', displayName: '日本語', isDefault: true),
  SupportedLanguage(id: 'zh_cn', displayName: '简体中文', isDefault: true),
  SupportedLanguage(id: 'ko_kr', displayName: '한국어', isDefault: true),
  SupportedLanguage(id: 'de_de', displayName: 'Deutsch', isDefault: true),
  SupportedLanguage(id: 'fr_fr', displayName: 'Français', isDefault: true),
  SupportedLanguage(id: 'es_es', displayName: 'Español', isDefault: true),
  SupportedLanguage(id: 'it_it', displayName: 'Italiano', isDefault: true),
  SupportedLanguage(
    id: 'pt_br',
    displayName: 'Português-Brasil',
    isDefault: true,
  ),
  SupportedLanguage(id: 'ru_ru', displayName: 'Русский', isDefault: true),
];
