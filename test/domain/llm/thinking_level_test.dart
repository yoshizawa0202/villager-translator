import 'package:flutter_test/flutter_test.dart';
import 'package:villager_translator/domain/llm/thinking_level.dart';

void main() {
  group('ThinkingLevel', () {
    test('識別子は off/on/low/medium/high/max の6段階(010 AC-04)', () {
      final ids = ThinkingLevel.values.map((l) => l.id).toList();
      expect(ids, equals(['off', 'on', 'low', 'medium', 'high', 'max']));
    });

    test('UI 表示名は OFF/ON/低/中/高/最大(010 §6.1)', () {
      expect(ThinkingLevel.off.displayName, 'OFF');
      expect(ThinkingLevel.on.displayName, 'ON');
      expect(ThinkingLevel.low.displayName, '低');
      expect(ThinkingLevel.medium.displayName, '中');
      expect(ThinkingLevel.high.displayName, '高');
      expect(ThinkingLevel.max.displayName, '最大');
    });

    test('fromId が既知の識別子から ThinkingLevel を解決する', () {
      expect(ThinkingLevel.fromId('off'), ThinkingLevel.off);
      expect(ThinkingLevel.fromId('on'), ThinkingLevel.on);
      expect(ThinkingLevel.fromId('low'), ThinkingLevel.low);
      expect(ThinkingLevel.fromId('medium'), ThinkingLevel.medium);
      expect(ThinkingLevel.fromId('high'), ThinkingLevel.high);
      expect(ThinkingLevel.fromId('max'), ThinkingLevel.max);
    });

    test('fromId は未知の識別子に対して例外を投げる', () {
      expect(() => ThinkingLevel.fromId('unknown'), throwsArgumentError);
      expect(() => ThinkingLevel.fromId(''), throwsArgumentError);
    });
  });
}
