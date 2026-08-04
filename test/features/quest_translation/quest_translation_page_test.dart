import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:villager_translator/domain/llm/llm_adapter.dart';
import 'package:villager_translator/domain/llm/llm_adapter_config.dart';
import 'package:villager_translator/domain/llm/llm_provider.dart';
import 'package:villager_translator/features/quest_translation/quest_translation_controller.dart';
import 'package:villager_translator/features/quest_translation/quest_translation_page.dart';
import 'package:villager_translator/features/settings/settings_controller.dart';
import 'package:villager_translator/infrastructure/llm/llm_adapter_factory.dart';
import 'package:villager_translator/infrastructure/llm/mock_llm_adapter.dart';
import 'package:villager_translator/infrastructure/questtranslation/quest_translation_orchestrator.dart';

import '../../test_support/in_memory_api_key_store.dart';
import '../../test_support/in_memory_settings_repository.dart';

class _FakeAdapterFactory implements LlmAdapterFactory {
  @override
  LlmAdapter create(LlmProvider provider, LlmAdapterConfig config) =>
      const MockLlmAdapter();
}

Future<void> _writeFile(String path, String content) async {
  final file = File(path);
  await file.parent.create(recursive: true);
  await file.writeAsString(content);
}

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp(
      'quest_translation_page_test_',
    );
    await _writeFile(
      p.join(tempDir.path, 'resources', 'betterquesting', 'lang', 'en_us.json'),
      '{"quest.a": "Quest A"}',
    );
    await _writeFile(
      p.join(tempDir.path, 'config', 'betterquesting', 'DefaultQuests.lang'),
      'quest.b=Quest B',
    );
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  Future<QuestTranslationController> pumpPage(WidgetTester tester) async {
    final settingsController = SettingsController(
      repository: InMemorySettingsRepository(),
      apiKeyStore: InMemoryApiKeyStore(),
    );
    await settingsController.load();
    await settingsController.setApiKey(LlmProvider.openai, 'test-key');

    final questController = QuestTranslationController(
      settingsController: settingsController,
      orchestrator: QuestTranslationOrchestrator(
        adapterFactory: _FakeAdapterFactory(),
      ),
    );

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<SettingsController>.value(
            value: settingsController,
          ),
        ],
        child: MaterialApp(
          home: QuestTranslationPage(controller: questController),
        ),
      ),
    );
    await tester.pumpAndSettle();

    return questController;
  }

  testWidgets('未選択→スキャン完了→翻訳完了の状態遷移と、テーブルのチェックボックス・検索が機能する', (tester) async {
    final controller = await pumpPage(tester);

    expect(find.text('未選択'), findsOneWidget);

    final scanButtonBefore = tester.widget<ElevatedButton>(
      find.byKey(const Key('scanButton')),
    );
    expect(scanButtonBefore.onPressed, isNull);

    await tester.enterText(
      find.byKey(const Key('profileDirectoryField')),
      tempDir.path,
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(controller.profileDirectory!.path, tempDir.path);

    await tester.runAsync(() => controller.scan());
    await tester.pumpAndSettle();

    expect(find.text('スキャン完了'), findsOneWidget);
    expect(
      find.byKey(
        const Key('questRow_resources/betterquesting/lang/en_us.json'),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(
        const Key('questRow_config/betterquesting/DefaultQuests.lang'),
      ),
      findsOneWidget,
    );
    expect(controller.selectedPaths, {
      'resources/betterquesting/lang/en_us.json',
      'config/betterquesting/DefaultQuests.lang',
    });

    // 部分一致検索。
    await tester.enterText(find.byKey(const Key('searchField')), 'Default');
    await tester.pumpAndSettle();
    expect(
      find.byKey(
        const Key('questRow_resources/betterquesting/lang/en_us.json'),
      ),
      findsNothing,
    );
    expect(
      find.byKey(
        const Key('questRow_config/betterquesting/DefaultQuests.lang'),
      ),
      findsOneWidget,
    );

    await tester.enterText(find.byKey(const Key('searchField')), '');
    await tester.pumpAndSettle();

    // チェックボックス列: DefaultQuests.lang の選択を解除する。
    await tester.tap(
      find.byKey(
        const Key('questRow_config/betterquesting/DefaultQuests.lang'),
      ),
    );
    await tester.pumpAndSettle();
    expect(controller.selectedPaths, {
      'resources/betterquesting/lang/en_us.json',
    });

    final translateButtonAfter = tester.widget<ElevatedButton>(
      find.byKey(const Key('translateButton')),
    );
    expect(translateButtonAfter.onPressed, isNotNull);

    await tester.runAsync(() => controller.translate());
    await tester.pumpAndSettle();

    expect(find.text('完了'), findsOneWidget);
    expect(find.byKey(const Key('translationResultSummary')), findsOneWidget);
    expect(controller.lastResult!.translationResult.translatedPaths, [
      'resources/betterquesting/lang/en_us.json',
    ]);
  });
}
