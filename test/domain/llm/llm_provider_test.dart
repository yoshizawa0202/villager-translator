import 'package:flutter_test/flutter_test.dart';
import 'package:villager_translator/domain/llm/llm_provider.dart';

void main() {
  group('LlmProvider', () {
    test('識別子は openai/anthropic/gemini の3種のみで、google は存在しない', () {
      final ids = LlmProvider.values.map((p) => p.id).toSet();
      expect(ids, equals({'openai', 'anthropic', 'gemini'}));
      expect(ids.contains('google'), isFalse);
    });

    test('fromId が既知の識別子から LlmProvider を解決する', () {
      expect(LlmProvider.fromId('openai'), LlmProvider.openai);
      expect(LlmProvider.fromId('anthropic'), LlmProvider.anthropic);
      expect(LlmProvider.fromId('gemini'), LlmProvider.gemini);
    });

    test('fromId は未知の識別子(google を含む)に対して例外を投げる', () {
      expect(() => LlmProvider.fromId('google'), throwsArgumentError);
      expect(() => LlmProvider.fromId('unknown'), throwsArgumentError);
    });
  });
}
