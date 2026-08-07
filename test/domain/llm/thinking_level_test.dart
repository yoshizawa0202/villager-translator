import 'package:flutter_test/flutter_test.dart';
import 'package:villager_translator/domain/llm/thinking_level.dart';

void main() {
  group('ThinkingLevel', () {
    test('識別子は off/low/medium/high の4種のみ', () {
      final ids = ThinkingLevel.values.map((l) => l.id).toSet();
      expect(ids, equals({'off', 'low', 'medium', 'high'}));
    });

    test('fromId が既知の識別子から ThinkingLevel を解決する', () {
      expect(ThinkingLevel.fromId('off'), ThinkingLevel.off);
      expect(ThinkingLevel.fromId('low'), ThinkingLevel.low);
      expect(ThinkingLevel.fromId('medium'), ThinkingLevel.medium);
      expect(ThinkingLevel.fromId('high'), ThinkingLevel.high);
    });

    test('fromId は未知の識別子に対して例外を投げる', () {
      expect(() => ThinkingLevel.fromId('unknown'), throwsArgumentError);
      expect(() => ThinkingLevel.fromId(''), throwsArgumentError);
    });
  });
}
