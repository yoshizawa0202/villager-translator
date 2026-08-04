import 'package:flutter_test/flutter_test.dart';
import 'package:villager_translator/domain/translation/diff_update.dart';

void main() {
  group('resolveDiffUpdateJob', () {
    final sourceEntries = {'a': '1', 'b': '2', 'c': '3'};

    test('対象言語ファイルが存在しない場合は全キーが翻訳対象になる', () {
      final job = resolveDiffUpdateJob(
        sourceEntries: sourceEntries,
        existingTargetEntries: null,
      );

      expect(job.keysToTranslate, sourceEntries);
      expect(job.isSkipped, isFalse);
    });

    test('一部キーが既存の場合は不足キーのみが翻訳対象になる', () {
      final job = resolveDiffUpdateJob(
        sourceEntries: sourceEntries,
        existingTargetEntries: {'a': '既存の翻訳'},
      );

      expect(job.keysToTranslate, {'b': '2', 'c': '3'});
      expect(job.isSkipped, isFalse);
    });

    test('全キーが既存の場合はジョブを作成せずスキップ扱いになる', () {
      final job = resolveDiffUpdateJob(
        sourceEntries: sourceEntries,
        existingTargetEntries: {'a': '1訳', 'b': '2訳', 'c': '3訳'},
      );

      expect(job.keysToTranslate, isEmpty);
      expect(job.isSkipped, isTrue);
    });
  });

  group('mergeDiffUpdateResult', () {
    test('既存キーの値は新たな翻訳結果によって上書きされない', () {
      final merged = mergeDiffUpdateResult(
        existingEntries: {'a': 'ユーザーによる手動修正'},
        newlyTranslatedEntries: {'a': '新しい翻訳(無視されるべき)', 'b': '新規翻訳'},
      );

      expect(merged, {'a': 'ユーザーによる手動修正', 'b': '新規翻訳'});
    });

    test('既存の内容と新規翻訳をマージした結果を返す', () {
      final merged = mergeDiffUpdateResult(
        existingEntries: {'a': '1訳'},
        newlyTranslatedEntries: {'b': '2訳', 'c': '3訳'},
      );

      expect(merged, {'a': '1訳', 'b': '2訳', 'c': '3訳'});
    });
  });
}
