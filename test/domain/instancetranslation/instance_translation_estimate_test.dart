import 'package:flutter_test/flutter_test.dart';
import 'package:villager_translator/domain/instancetranslation/instance_translation_estimate.dart';
import 'package:villager_translator/domain/instancetranslation/instance_translation_mode.dart';
import 'package:villager_translator/domain/settings/existing_translation_policy.dart';

import '../../test_support/instance_translation_fixtures.dart';

void main() {
  test('カテゴリごとの件数・文字列数と合計を集計する(012 §6、AC-06)', () {
    final estimate = estimateInstanceTranslation(
      buildTestPlan(
        rootPath: 'D:/mc',
        mods: [
          buildModEntry(id: 'a', sourceEntries: {'1': 'A', '2': 'B'}),
          buildModEntry(id: 'b', sourceEntries: {'1': 'C'}),
        ],
        quests: [
          buildQuestEntry(
            relativePath: 'q.json',
            sourceEntries: {'1': 'Q', '2': 'R', '3': 'S'},
          ),
        ],
        guidebooks: [
          buildBookEntry(
            modId: 'ars',
            bookId: 'notebook',
            sourceEntries: {'1': 'P'},
          ),
        ],
      ),
    );

    final byLabel = {for (final c in estimate.categories) c.label: c};
    expect(byLabel['MOD']!.itemCount, 2);
    expect(byLabel['MOD']!.stringCount, 3);
    expect(byLabel['クエスト']!.itemCount, 1);
    expect(byLabel['クエスト']!.stringCount, 3);
    expect(byLabel['ガイドブック']!.itemCount, 1);
    expect(byLabel['ガイドブック']!.stringCount, 1);

    expect(estimate.totalItemCount, 4);
    expect(estimate.totalStringCount, 7);
  });

  test('OFF にしたカテゴリは集計に現れない(012 AC-02)', () {
    final estimate = estimateInstanceTranslation(
      buildTestPlan(
        rootPath: 'D:/mc',
        mods: [buildModEntry(id: 'a')],
        quests: [buildQuestEntry(relativePath: 'q.json')],
        translateQuests: false,
        translateGuidebooks: false,
      ),
    );

    expect(estimate.categories.map((c) => c.label).toList(), ['MOD']);
  });

  test('「未翻訳のみ」では翻訳済み対象を件数・文字列数から除外する(012 AC-06)', () {
    final estimate = estimateInstanceTranslation(
      buildTestPlan(
        rootPath: 'D:/mc',
        mode: InstanceTranslationMode.untranslatedOnly,
        mods: [
          buildModEntry(id: 'a', hasExistingTranslation: true),
          buildModEntry(id: 'b'),
        ],
        guidebooks: [
          buildBookEntry(
            modId: 'ars',
            bookId: 'notebook',
            hasExistingTranslation: true,
          ),
        ],
        translateQuests: false,
      ),
    );

    final byLabel = {for (final c in estimate.categories) c.label: c};
    expect(byLabel['MOD']!.itemCount, 1);
    expect(byLabel['MOD']!.stringCount, 1);
    expect(byLabel['ガイドブック']!.itemCount, 0);
    expect(estimate.isUpperBound, isFalse);
  });

  test('「差分更新」では全キーを上限値として表示する(012 §6)', () {
    final estimate = estimateInstanceTranslation(
      buildTestPlan(
        rootPath: 'D:/mc',
        mods: [buildModEntry(id: 'a', hasExistingTranslation: true)],
        translateQuests: false,
        translateGuidebooks: false,
      ),
    );

    expect(estimate.categories.single.itemCount, 1);
    expect(estimate.isUpperBound, isTrue);
  });

  test('翻訳モードは ExistingTranslationPolicy へ 1 対 1 で写像される(012 AC-03)', () {
    expect(
      InstanceTranslationMode.untranslatedOnly.policy,
      ExistingTranslationPolicy.skip,
    );
    expect(
      InstanceTranslationMode.diffUpdate.policy,
      ExistingTranslationPolicy.diffUpdate,
    );
    expect(
      InstanceTranslationMode.retranslateAll.policy,
      ExistingTranslationPolicy.retranslateAll,
    );

    for (final policy in ExistingTranslationPolicy.values) {
      expect(InstanceTranslationMode.fromPolicy(policy).policy, policy);
    }
  });

  test('全カテゴリ OFF のとき対象が無いと判定される(012 AC-02)', () {
    final plan = buildTestPlan(
      rootPath: 'D:/mc',
      mods: [buildModEntry(id: 'a')],
      translateMods: false,
      translateQuests: false,
      translateGuidebooks: false,
    );

    expect(plan.hasAnyTarget, isFalse);
    expect(plan.effectiveMods, isEmpty);
  });
}
