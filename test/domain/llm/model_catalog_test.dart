import 'package:flutter_test/flutter_test.dart';
import 'package:villager_translator/domain/llm/llm_provider.dart';
import 'package:villager_translator/domain/llm/model_catalog.dart';
import 'package:villager_translator/domain/llm/thinking_level.dart';

void main() {
  group('kModelCatalog', () {
    test('すべてのモデルの supportedThinkingLevels は off を含む', () {
      for (final models in kModelCatalog.values) {
        for (final model in models) {
          expect(
            model.supportedThinkingLevels,
            contains(ThinkingLevel.off),
            reason: '${model.id} は off を含む必要がある',
          );
        }
      }
    });

    test('既定モデル(kDefaultModel)はすべて kModelCatalog に存在する', () {
      for (final entry in kDefaultModel.entries) {
        expect(modelInfoFor(entry.key, entry.value), isNotNull);
      }
    });
  });

  group('ModelInfo.supportsThinking', () {
    test('off のみの場合は false', () {
      const info = ModelInfo(id: 'x');
      expect(info.supportsThinking, isFalse);
    });

    test('off 以外を含む場合は true', () {
      const info = ModelInfo(
        id: 'x',
        supportedThinkingLevels: [ThinkingLevel.off, ThinkingLevel.high],
      );
      expect(info.supportsThinking, isTrue);
    });
  });

  group('modelInfoFor', () {
    test('カタログに存在するモデルの ModelInfo を返す', () {
      final info = modelInfoFor(LlmProvider.openai, 'gpt-5.6-sol');
      expect(info, isNotNull);
      expect(info!.id, 'gpt-5.6-sol');
    });

    test('カタログに存在しないモデル ID には null を返す', () {
      expect(modelInfoFor(LlmProvider.openai, 'unknown-model'), isNull);
      expect(modelInfoFor(LlmProvider.openai, kCustomModelSentinel), isNull);
    });
  });
}
