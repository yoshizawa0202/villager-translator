import 'instance_translation_mode.dart';
import 'instance_translation_plan.dart';

/// 翻訳前サマリーのカテゴリ 1 件分の集計
/// (012-instance-batch-translation.md §6)。
class InstanceTranslationCategoryEstimate {
  const InstanceTranslationCategoryEstimate({
    required this.label,
    required this.itemCount,
    required this.stringCount,
  });

  /// 画面に表示するカテゴリ名(`MOD`、`FTB Quests` など)。
  final String label;

  /// 対象件数。
  final int itemCount;

  /// 翻訳対象文字列数(`sourceEntries` のエントリ数の合計)。
  final int stringCount;
}

/// 翻訳前サマリー全体の集計(§6)。
class InstanceTranslationEstimate {
  const InstanceTranslationEstimate({
    required this.categories,
    required this.isUpperBound,
  });

  final List<InstanceTranslationCategoryEstimate> categories;

  /// 表示値が上限値かどうか。
  ///
  /// 翻訳モードが「差分更新」の場合、既存キーの実チェックは翻訳直前に
  /// オーケストレーター内部で行われるため、サマリーでは全キーを上限値として
  /// 表示し、その旨を注記する(§6)。
  final bool isUpperBound;

  /// 全カテゴリの合計文字列数。
  int get totalStringCount =>
      categories.fold(0, (sum, c) => sum + c.stringCount);

  /// 全カテゴリの合計件数。
  int get totalItemCount => categories.fold(0, (sum, c) => sum + c.itemCount);
}

/// [plan] から翻訳前サマリーの集計を作る(§6)。
///
/// `ModScanEntry.sourceEntries`、`QuestScanEntry.sourceEntries`、
/// `PatchouliBookEntry.sourceEntries` はいずれも `Map<String, String>` である
/// ため、件数とエントリ数を数えるだけで足りる。新しい判定ロジックは持たない。
///
/// 翻訳モードが「未翻訳のみ」の場合、既に翻訳済みの対象を件数・文字列数から
/// 除外する(AC-06)。クエストは既存翻訳の判定情報を持たないため除外しない
/// (SNBT は既存翻訳の判定が不能で、既存実装でも常に再翻訳として扱われる)。
InstanceTranslationEstimate estimateInstanceTranslation(
  InstanceTranslationPlan plan,
) {
  final skipTranslated = plan.mode == InstanceTranslationMode.untranslatedOnly;

  final mods = plan.effectiveMods
      .where((e) => !skipTranslated || !e.hasExistingTranslation)
      .toList();
  final guidebooks = plan.effectiveGuidebooks
      .where((e) => !skipTranslated || !e.hasExistingTranslation)
      .toList();
  final quests = plan.effectiveQuests;

  final categories = <InstanceTranslationCategoryEstimate>[];

  if (plan.translateMods) {
    categories.add(
      InstanceTranslationCategoryEstimate(
        label: 'MOD',
        itemCount: mods.length,
        stringCount: mods.fold(0, (sum, e) => sum + e.sourceEntries.length),
      ),
    );
  }
  if (plan.translateQuests) {
    categories.add(
      InstanceTranslationCategoryEstimate(
        label: 'クエスト',
        itemCount: quests.length,
        stringCount: quests.fold(0, (sum, e) => sum + e.sourceEntries.length),
      ),
    );
  }
  if (plan.translateGuidebooks) {
    categories.add(
      InstanceTranslationCategoryEstimate(
        label: 'ガイドブック',
        itemCount: guidebooks.length,
        stringCount: guidebooks.fold(
          0,
          (sum, e) => sum + e.sourceEntries.length,
        ),
      ),
    );
  }

  return InstanceTranslationEstimate(
    categories: categories,
    isUpperBound: plan.mode == InstanceTranslationMode.diffUpdate,
  );
}
