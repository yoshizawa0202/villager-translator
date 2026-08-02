import 'package:flutter_test/flutter_test.dart';
import 'package:villager_translator/infrastructure/llm/mock_llm_adapter.dart';

void main() {
  group('MockLlmAdapter', () {
    test('translate はネットワークを使わず即座に固定文字列を返す', () async {
      const adapter = MockLlmAdapter();
      final result = await adapter.translate(
        content: {'a': 'Hello'},
        targetLanguage: 'ja',
      );
      expect(result, {'a': '[MOCK] Hello'});
    });

    test('validateApiKey は即座に真偽を返す', () async {
      const adapter = MockLlmAdapter();
      expect(await adapter.validateApiKey('any-key'), isTrue);
      expect(await adapter.validateApiKey(''), isFalse);
    });
  });
}
