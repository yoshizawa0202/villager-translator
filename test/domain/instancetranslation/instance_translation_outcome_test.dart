import 'package:flutter_test/flutter_test.dart';
import 'package:villager_translator/domain/common/translation_summary.dart';
import 'package:villager_translator/domain/instancetranslation/instance_translation_outcome.dart';

import '../../test_support/instance_translation_fixtures.dart';

InstanceTranslationOutcome _outcome({
  List<String> failedMods = const [],
  List<String> failedQuests = const [],
  List<String> failedGuidebooks = const [],
  List<String> successMods = const [],
  List<String> skippedMods = const [],
}) => InstanceTranslationOutcome(
  sessionId: 'session-1',
  categories: [
    InstanceTranslationCategoryOutcome(
      category: InstanceTranslationCategory.mods,
      successIds: successMods,
      failedIds: failedMods,
      skippedIds: skippedMods,
    ),
    InstanceTranslationCategoryOutcome(
      category: InstanceTranslationCategory.quests,
      failedIds: failedQuests,
    ),
    InstanceTranslationCategoryOutcome(
      category: InstanceTranslationCategory.guidebooks,
      failedIds: failedGuidebooks,
    ),
  ],
  summary: TranslationSummary(
    sessionId: 'session-1',
    targetLanguage: 'ja_jp',
    createdAt: DateTime(2026, 8, 24),
    items: const [],
  ),
  cancelled: false,
);

void main() {
  test('成功・失敗・スキップの件数を全カテゴリで合算する(012 §10、AC-13)', () {
    final outcome = _outcome(
      successMods: ['a', 'b'],
      failedMods: ['c'],
      skippedMods: ['d', 'e', 'f'],
      failedQuests: ['q.json'],
    );

    expect(outcome.successCount, 2);
    expect(outcome.failureCount, 2);
    expect(outcome.skippedCount, 3);
    expect(outcome.hasFailures, isTrue);
  });

  test('再試行計画は失敗した対象だけに絞られる(012 AC-13)', () {
    final plan = buildTestPlan(
      rootPath: 'D:/mc',
      mods: [
        buildModEntry(id: 'a'),
        buildModEntry(id: 'b'),
      ],
      quests: [
        buildQuestEntry(relativePath: 'q1.json'),
        buildQuestEntry(relativePath: 'q2.json'),
      ],
      guidebooks: [
        buildBookEntry(modId: 'ars', bookId: 'notebook'),
        buildBookEntry(modId: 'malum', bookId: 'encyclopedia'),
      ],
    );

    final retry = buildRetryPlan(
      plan,
      _outcome(
        successMods: ['a'],
        failedMods: ['b'],
        failedGuidebooks: ['malum:encyclopedia'],
      ),
    );

    expect(retry.mods.map((e) => e.modInfo.id).toList(), ['b']);
    expect(retry.quests, isEmpty);
    expect(retry.guidebooks.map((e) => e.bookKey).toList(), [
      'malum:encyclopedia',
    ]);

    // 対象が残らないカテゴリは自動的に OFF になる。
    expect(retry.translateMods, isTrue);
    expect(retry.translateQuests, isFalse);
    expect(retry.translateGuidebooks, isTrue);

    // 対象一覧以外の指定は元の計画から引き継ぐ。
    expect(retry.targetLanguageId, plan.targetLanguageId);
    expect(retry.provider, plan.provider);
    expect(retry.model, plan.model);
    expect(retry.mode, plan.mode);
  });

  test('失敗が 1 件も無ければ再試行計画は空になる', () {
    final plan = buildTestPlan(
      rootPath: 'D:/mc',
      mods: [buildModEntry(id: 'a')],
    );

    final retry = buildRetryPlan(plan, _outcome(successMods: ['a']));

    expect(retry.hasAnyTarget, isFalse);
  });
}
