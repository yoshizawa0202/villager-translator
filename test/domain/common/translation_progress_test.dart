import 'package:flutter_test/flutter_test.dart';
import 'package:villager_translator/domain/common/translation_progress.dart';

void main() {
  group('ChunkProgress', () {
    test('fraction と percent を算出する', () {
      const progress = ChunkProgress(completedChunks: 1, totalChunks: 4);
      expect(progress.fraction, 0.25);
      expect(progress.percent, 25);
    });

    test('総チャンク数が0の場合は完了扱い(1.0)とする', () {
      const progress = ChunkProgress(completedChunks: 0, totalChunks: 0);
      expect(progress.fraction, 1.0);
    });
  });

  group('OverallProgress', () {
    test('「X / Y 件完了 (Z%)」形式のラベルを生成する', () {
      const progress = OverallProgress(completedItems: 3, totalItems: 10);
      expect(progress.percent, 30);
      expect(progress.label, '3 / 10 件完了 (30%)');
    });

    test('総件数が0の場合は100%として扱う', () {
      const progress = OverallProgress(completedItems: 0, totalItems: 0);
      expect(progress.percent, 100);
      expect(progress.label, '0 / 0 件完了 (100%)');
    });
  });
}
