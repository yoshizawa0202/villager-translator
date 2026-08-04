import 'package:flutter_test/flutter_test.dart';
import 'package:villager_translator/domain/common/session_id.dart';

void main() {
  group('defaultSessionId', () {
    test('コロン・ピリオドをハイフンへ置換したISO8601形式の文字列を返す', () {
      final id = defaultSessionId(DateTime(2026, 8, 4, 12, 34, 56, 789));
      expect(id, isNot(contains(':')));
      expect(id, isNot(contains('.')));
      expect(id, startsWith('2026-08-04T12-34-56'));
    });

    test('時系列が新しいほど文字列としても大きくなる(履歴の降順ソートに使える)', () {
      final earlier = defaultSessionId(DateTime(2026, 8, 4, 10, 0, 0));
      final later = defaultSessionId(DateTime(2026, 8, 4, 11, 0, 0));
      expect(later.compareTo(earlier), greaterThan(0));
    });
  });
}
