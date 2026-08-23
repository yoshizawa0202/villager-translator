import 'package:flutter_test/flutter_test.dart';
import 'package:villager_translator/domain/llm/llm_provider.dart';

void main() {
  group('LlmProvider', () {
    test('識別子は6プロバイダーで、google は存在しない(010 §5)', () {
      final ids = LlmProvider.values.map((p) => p.id).toSet();
      expect(
        ids,
        equals({'openai', 'anthropic', 'gemini', 'deepseek', 'qwen', 'kimi'}),
      );
      expect(ids.contains('google'), isFalse);
    });

    test('識別子は重複しない(API キーの独立保存の前提、010 AC-03)', () {
      final ids = LlmProvider.values.map((p) => p.id).toList();
      expect(ids.toSet().length, ids.length);
    });

    test('fromId が既知の識別子から LlmProvider を解決する', () {
      expect(LlmProvider.fromId('openai'), LlmProvider.openai);
      expect(LlmProvider.fromId('anthropic'), LlmProvider.anthropic);
      expect(LlmProvider.fromId('gemini'), LlmProvider.gemini);
      expect(LlmProvider.fromId('deepseek'), LlmProvider.deepseek);
      expect(LlmProvider.fromId('qwen'), LlmProvider.qwen);
      expect(LlmProvider.fromId('kimi'), LlmProvider.kimi);
    });

    test('fromId は未知の識別子(google を含む)に対して例外を投げる', () {
      expect(() => LlmProvider.fromId('google'), throwsArgumentError);
      expect(() => LlmProvider.fromId('unknown'), throwsArgumentError);
    });
  });
}
