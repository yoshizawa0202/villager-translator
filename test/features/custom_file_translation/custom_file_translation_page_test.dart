import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:villager_translator/domain/llm/llm_adapter.dart';
import 'package:villager_translator/domain/llm/llm_adapter_config.dart';
import 'package:villager_translator/domain/llm/llm_provider.dart';
import 'package:villager_translator/features/custom_file_translation/custom_file_translation_controller.dart';
import 'package:villager_translator/features/custom_file_translation/custom_file_translation_page.dart';
import 'package:villager_translator/features/settings/settings_controller.dart';
import 'package:villager_translator/infrastructure/customfiletranslation/custom_file_translation_orchestrator.dart';
import 'package:villager_translator/infrastructure/llm/llm_adapter_factory.dart';
import 'package:villager_translator/infrastructure/llm/mock_llm_adapter.dart';

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
      'custom_file_translation_page_test_',
    );
    await _writeFile(p.join(tempDir.path, 'a.json'), '{"title": "Hello"}');
    await _writeFile(p.join(tempDir.path, 'nested', 'b.snbt'), 'raw content');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  Future<CustomFileTranslationController> pumpPage(WidgetTester tester) async {
    final settingsController = SettingsController(
      repository: InMemorySettingsRepository(),
      apiKeyStore: InMemoryApiKeyStore(),
    );
    await settingsController.load();
    await settingsController.setApiKey(LlmProvider.openai, 'test-key');

    final customFileController = CustomFileTranslationController(
      settingsController: settingsController,
      orchestrator: CustomFileTranslationOrchestrator(
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
          home: CustomFileTranslationPage(controller: customFileController),
        ),
      ),
    );
    await tester.pumpAndSettle();

    return customFileController;
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
    expect(find.byKey(const Key('customFileRow_a.json')), findsOneWidget);
    expect(
      find.byKey(const Key('customFileRow_nested/b.snbt')),
      findsOneWidget,
    );
    expect(controller.selectedPaths, {'a.json', 'nested/b.snbt'});

    // 部分一致検索。
    await tester.enterText(find.byKey(const Key('searchField')), 'nested');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('customFileRow_a.json')), findsNothing);
    expect(
      find.byKey(const Key('customFileRow_nested/b.snbt')),
      findsOneWidget,
    );

    await tester.enterText(find.byKey(const Key('searchField')), '');
    await tester.pumpAndSettle();

    // チェックボックス列: nested/b.snbt の選択を解除する。
    await tester.tap(find.byKey(const Key('customFileRow_nested/b.snbt')));
    await tester.pumpAndSettle();
    expect(controller.selectedPaths, {'a.json'});

    final translateButtonAfter = tester.widget<ElevatedButton>(
      find.byKey(const Key('translateButton')),
    );
    expect(translateButtonAfter.onPressed, isNotNull);

    await tester.runAsync(() => controller.translate());
    await tester.pumpAndSettle();

    expect(find.text('完了'), findsOneWidget);
    expect(find.byKey(const Key('translationResultSummary')), findsOneWidget);
    expect(controller.lastResult!.translationResult.translatedPaths, [
      'a.json',
    ]);
  });
}
