import '../settings/existing_translation_policy.dart';

/// 一括翻訳画面で選ぶ「既存翻訳の扱い」
/// (012-instance-batch-translation.md §5)。
///
/// 内部表現は既存の [ExistingTranslationPolicy] へ写像し、新しい列挙を実質的に
/// 増やさない(同じ概念を表す型が 2 つ存在しないよう、画面表記だけを issue の
/// 用語に合わせる)。
enum InstanceTranslationMode {
  /// 対象言語ファイルが既に存在する対象は翻訳しない。
  untranslatedOnly('未翻訳のみ', ExistingTranslationPolicy.skip),

  /// 不足しているキーのみを翻訳して追記する(既定)。
  diffUpdate('差分更新', ExistingTranslationPolicy.diffUpdate),

  /// 既存の有無に関わらず全キーを翻訳し直す。
  retranslateAll('すべて再翻訳', ExistingTranslationPolicy.retranslateAll);

  const InstanceTranslationMode(this.displayName, this.policy);

  /// 画面に表示する名称。
  final String displayName;

  /// 各オーケストレーターへ渡す既存の設定値。
  final ExistingTranslationPolicy policy;

  /// [ExistingTranslationPolicy] から対応するモードを解決する。
  static InstanceTranslationMode fromPolicy(ExistingTranslationPolicy policy) {
    for (final mode in InstanceTranslationMode.values) {
      if (mode.policy == policy) return mode;
    }
    return InstanceTranslationMode.diffUpdate;
  }
}
