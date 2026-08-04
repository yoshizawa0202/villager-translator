import 'package:flutter_test/flutter_test.dart';
import 'package:villager_translator/domain/common/cancellation_token.dart';

void main() {
  group('CancellationToken', () {
    test('初期状態ではキャンセルされていない', () {
      final token = CancellationToken();
      expect(token.isCancelled, isFalse);
    });

    test('cancel() を呼ぶと isCancelled が真になる', () {
      final token = CancellationToken();
      token.cancel();
      expect(token.isCancelled, isTrue);
    });

    test('cancel() を複数回呼んでも問題ない', () {
      final token = CancellationToken();
      token.cancel();
      token.cancel();
      expect(token.isCancelled, isTrue);
    });
  });
}
