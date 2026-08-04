import 'package:flutter_test/flutter_test.dart';
import 'package:villager_translator/domain/common/translation_summary.dart';

void main() {
  group('TranslationSummary', () {
    test('toJson/fromJson で往復できる', () {
      final summary = TranslationSummary(
        sessionId: '2026-08-04T12-00-00',
        targetLanguage: 'ja_jp',
        createdAt: DateTime(2026, 8, 4, 12),
        items: const [
          TranslationSummaryItem(
            type: TranslationTargetType.mod,
            id: 'example_mod',
            displayName: 'Example Mod',
            targetLanguage: 'ja_jp',
            outputPath: 'resourcepacks/x/assets/example_mod/lang/ja_jp.json',
            success: true,
            translatedKeyCount: 10,
            totalKeyCount: 10,
          ),
          TranslationSummaryItem(
            type: TranslationTargetType.mod,
            id: 'failed_mod',
            targetLanguage: 'ja_jp',
            success: false,
            translatedKeyCount: 0,
            totalKeyCount: 5,
          ),
        ],
      );

      final restored = TranslationSummary.fromJson(summary.toJson());

      expect(restored.sessionId, summary.sessionId);
      expect(restored.targetLanguage, summary.targetLanguage);
      expect(restored.createdAt, summary.createdAt);
      expect(restored.items.length, 2);
      expect(restored.items[0].id, 'example_mod');
      expect(restored.items[0].displayName, 'Example Mod');
      expect(restored.items[1].success, isFalse);
    });

    test('成功/失敗/合計件数を算出する', () {
      final summary = TranslationSummary(
        sessionId: 's',
        targetLanguage: 'ja_jp',
        createdAt: DateTime(2026, 8, 4),
        items: const [
          TranslationSummaryItem(
            type: TranslationTargetType.quest,
            id: 'a',
            targetLanguage: 'ja_jp',
            success: true,
            translatedKeyCount: 1,
            totalKeyCount: 1,
          ),
          TranslationSummaryItem(
            type: TranslationTargetType.quest,
            id: 'b',
            targetLanguage: 'ja_jp',
            success: false,
            translatedKeyCount: 0,
            totalKeyCount: 1,
          ),
        ],
      );

      expect(summary.successCount, 1);
      expect(summary.failureCount, 1);
      expect(summary.totalCount, 2);
    });

    test('欠損・不正なJSONは安全側へフォールバックする', () {
      final restored = TranslationSummary.fromJson(const {});
      expect(restored.sessionId, '');
      expect(restored.items, isEmpty);

      final itemRestored = TranslationSummaryItem.fromJson(const {
        'type': 'unknown_type',
      });
      expect(itemRestored.type, TranslationTargetType.custom);
      expect(itemRestored.success, isFalse);
      expect(itemRestored.translatedKeyCount, 0);
    });
  });
}
