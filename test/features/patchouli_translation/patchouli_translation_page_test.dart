import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:villager_translator/domain/llm/llm_adapter.dart';
import 'package:villager_translator/domain/llm/llm_adapter_config.dart';
import 'package:villager_translator/domain/llm/llm_provider.dart';
import 'package:villager_translator/features/patchouli_translation/patchouli_translation_controller.dart';
import 'package:villager_translator/features/patchouli_translation/patchouli_translation_page.dart';
import 'package:villager_translator/features/settings/settings_controller.dart';
import 'package:villager_translator/infrastructure/llm/llm_adapter_factory.dart';
import 'package:villager_translator/infrastructure/llm/mock_llm_adapter.dart';
import 'package:villager_translator/infrastructure/patchoulitranslation/patchouli_translation_orchestrator.dart';

import '../../test_support/fake_jar_builder.dart';
import '../../test_support/in_memory_api_key_store.dart';
import '../../test_support/in_memory_settings_repository.dart';

class _FakeAdapterFactory implements LlmAdapterFactory {
  @override
  LlmAdapter create(LlmProvider provider, LlmAdapterConfig config) =>
      const MockLlmAdapter();
}

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp(
      'patchouli_translation_page_test_',
    );
    await writeFakeJar(File(p.join(tempDir.path, 'mods', 'amod.jar')), {
      'assets/amod/patchouli_books/guide/en_us/book.json':
          '{"name": "A Guide"}',
    });
    await writeFakeJar(File(p.join(tempDir.path, 'mods', 'zmod.jar')), {
      'assets/zmod/patchouli_books/guide/en_us/book.json':
          '{"name": "Z Guide"}',
    });
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  Future<PatchouliTranslationController> pumpPage(WidgetTester tester) async {
    final settingsController = SettingsController(
      repository: InMemorySettingsRepository(),
      apiKeyStore: InMemoryApiKeyStore(),
    );
    await settingsController.load();
    await settingsController.setApiKey(LlmProvider.openai, 'test-key');

    final patchouliController = PatchouliTranslationController(
      settingsController: settingsController,
      orchestrator: PatchouliTranslationOrchestrator(
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
          home: PatchouliTranslationPage(controller: patchouliController),
        ),
      ),
    );
    await tester.pumpAndSettle();

    return patchouliController;
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

    final scanButtonAfter = tester.widget<ElevatedButton>(
      find.byKey(const Key('scanButton')),
    );
    expect(scanButtonAfter.onPressed, isNotNull);

    await tester.runAsync(() => controller.scan());
    await tester.pumpAndSettle();

    expect(find.text('スキャン完了'), findsOneWidget);
    expect(find.byKey(const Key('patchouliRow_amod:guide')), findsOneWidget);
    expect(find.byKey(const Key('patchouliRow_zmod:guide')), findsOneWidget);
    expect(controller.selectedBookKeys, {'amod:guide', 'zmod:guide'});

    // 部分一致検索: "zmod" で絞り込む。
    await tester.enterText(find.byKey(const Key('searchField')), 'zmod');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('patchouliRow_amod:guide')), findsNothing);
    expect(find.byKey(const Key('patchouliRow_zmod:guide')), findsOneWidget);

    await tester.enterText(find.byKey(const Key('searchField')), '');
    await tester.pumpAndSettle();

    // チェックボックス列: zmod:guide の選択を解除する。
    await tester.tap(find.byKey(const Key('patchouliRow_zmod:guide')));
    await tester.pumpAndSettle();
    expect(controller.selectedBookKeys, {'amod:guide'});

    final translateButtonAfter = tester.widget<ElevatedButton>(
      find.byKey(const Key('translateButton')),
    );
    expect(translateButtonAfter.onPressed, isNotNull);

    await tester.runAsync(() => controller.translate());
    await tester.pumpAndSettle();

    expect(find.text('完了'), findsOneWidget);
    expect(find.byKey(const Key('translationResultSummary')), findsOneWidget);
    expect(controller.lastResult!.translationResult.translatedBookKeys, [
      'amod:guide',
    ]);
  });
}
