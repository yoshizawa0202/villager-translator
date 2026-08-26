import '../common/translation_summary.dart';
import 'instance_translation_plan.dart';

/// 一括翻訳のカテゴリ(処理順、012-instance-batch-translation.md §7)。
enum InstanceTranslationCategory {
  mods('MOD'),
  quests('クエスト'),
  guidebooks('ガイドブック');

  const InstanceTranslationCategory(this.displayName);

  final String displayName;
}

/// カテゴリ 1 件分の結果(§10)。
///
/// 「成功」は翻訳が完了し出力へ反映された対象、「失敗」は例外またはリトライ上限
/// 超過により反映されなかった対象、「スキップ」は翻訳モードにより対象外となった
/// 対象とする。
class InstanceTranslationCategoryOutcome {
  const InstanceTranslationCategoryOutcome({
    required this.category,
    this.successIds = const [],
    this.failedIds = const [],
    this.skippedIds = const [],
    this.outputLocations = const [],
    this.backupLocation,
    this.error,
    this.executed = true,
  });

  /// カテゴリが OFF、またはキャンセルにより開始されなかったことを表す結果。
  factory InstanceTranslationCategoryOutcome.notExecuted(
    InstanceTranslationCategory category,
  ) => InstanceTranslationCategoryOutcome(category: category, executed: false);

  final InstanceTranslationCategory category;

  /// 出力へ反映された対象の識別子(MOD JAR相対パス / クエスト相対パス /
  /// `modId:bookId`)。
  final List<String> successIds;

  /// 反映されなかった対象の識別子([buildRetryPlan] の絞り込みに使う)。
  final List<String> failedIds;

  /// 翻訳モードにより対象外となった対象の識別子。
  final List<String> skippedIds;

  /// 出力検証(§7)で確認した出力先(リソースパックのディレクトリ、書き込んだ
  /// クエストファイル、更新した JAR)。
  final List<String> outputLocations;

  /// バックアップの保存先。
  final String? backupLocation;

  /// カテゴリ全体が例外で失敗した場合の例外(§10: 後続カテゴリは継続する)。
  final Object? error;

  /// このカテゴリの処理を実行したかどうか。
  final bool executed;
}

/// 一括翻訳 1 回分の結果(§10、§12)。
class InstanceTranslationOutcome {
  const InstanceTranslationOutcome({
    required this.sessionId,
    required this.categories,
    required this.summary,
    required this.cancelled,
  });

  final String sessionId;
  final List<InstanceTranslationCategoryOutcome> categories;

  /// 3 カテゴリの結果を連結した統合サマリー(§8、AC-09)。
  final TranslationSummary summary;

  /// 利用者のキャンセルにより途中で停止したかどうか(AC-11)。
  final bool cancelled;

  int get successCount =>
      categories.fold(0, (sum, c) => sum + c.successIds.length);

  int get failureCount =>
      categories.fold(0, (sum, c) => sum + c.failedIds.length);

  int get skippedCount =>
      categories.fold(0, (sum, c) => sum + c.skippedIds.length);

  bool get hasFailures => failureCount > 0;

  InstanceTranslationCategoryOutcome? outcomeFor(
    InstanceTranslationCategory category,
  ) {
    for (final outcome in categories) {
      if (outcome.category == category) return outcome;
    }
    return null;
  }
}

/// 失敗した対象だけに絞った再試行用の計画を組み立てる(§10、AC-13)。
///
/// 再試行専用の実行経路は作らず、同じ [InstanceTranslationPlan] を通して
/// 同じ経路を再実行する。ここでの再試行は「対象 1 件単位の再実行」であり、
/// `lib/domain/translation/retry_policy.dart` が担うチャンク単位の自動リトライ
/// とは別レイヤである。
InstanceTranslationPlan buildRetryPlan(
  InstanceTranslationPlan plan,
  InstanceTranslationOutcome outcome,
) {
  final failedMods =
      outcome.outcomeFor(InstanceTranslationCategory.mods)?.failedIds ??
      const <String>[];
  final failedQuests =
      outcome.outcomeFor(InstanceTranslationCategory.quests)?.failedIds ??
      const <String>[];
  final failedGuidebooks =
      outcome.outcomeFor(InstanceTranslationCategory.guidebooks)?.failedIds ??
      const <String>[];

  final mods = plan.mods
      .where((e) => failedMods.contains(e.jarRelativePath))
      .toList();
  final quests = plan.quests
      .where((e) => failedQuests.contains(e.relativePath))
      .toList();
  final guidebooks = plan.guidebooks
      .where((e) => failedGuidebooks.contains(e.bookKey))
      .toList();

  return plan.copyWith(
    mods: mods,
    quests: quests,
    guidebooks: guidebooks,
    translateMods: mods.isNotEmpty,
    translateQuests: quests.isNotEmpty,
    translateGuidebooks: guidebooks.isNotEmpty,
  );
}
