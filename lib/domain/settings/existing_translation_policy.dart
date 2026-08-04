/// 既存翻訳の扱い(feature-spec.md §4.2)。
enum ExistingTranslationPolicy {
  /// 対象言語ファイルが既に存在する場合、翻訳しない。
  skip,

  /// 不足しているキーのみを翻訳して追記する(既定)。
  diffUpdate,

  /// 既存の有無に関わらず、常に全キーを翻訳し直す。
  retranslateAll;

  /// 設定ファイルに保存する文字列表現。
  String toJsonValue() => name;

  /// 保存済みの文字列から復元する。未知の値は既定の [diffUpdate] にフォールバックする。
  static ExistingTranslationPolicy fromJsonValue(String? value) {
    return ExistingTranslationPolicy.values.firstWhere(
      (e) => e.name == value,
      orElse: () => ExistingTranslationPolicy.diffUpdate,
    );
  }
}
