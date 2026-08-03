import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:villager_translator/domain/llm/llm_adapter.dart';
import 'package:villager_translator/domain/llm/llm_adapter_config.dart';
import 'package:villager_translator/domain/llm/llm_provider.dart';
import 'package:villager_translator/features/mod_translation/mod_translation_controller.dart';
import 'package:villager_translator/features/mod_translation/mod_translation_page.dart';
import 'package:villager_translator/features/settings/settings_controller.dart';
import 'package:villager_translator/infrastructure/llm/llm_adapter_factory.dart';
import 'package:villager_translator/infrastructure/llm/mock_llm_adapter.dart';
import 'package:villager_translator/infrastructure/modtranslation/mod_translation_orchestrator.dart';

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
      'mod_translation_page_test_',
    );
    await writeFakeJar(File(p.join(tempDir.path, 'mods', 'moda.jar')), {
      'fabric.mod.json': '{"id": "moda", "name": "Mod A", "version": "1.0"}',
      'assets/moda/lang/en_us.json': '{"item.a": "Item A"}',
    });
    await writeFakeJar(File(p.join(tempDir.path, 'mods', 'zmod.jar')), {
      'fabric.mod.json': '{"id": "zmod", "name": "Zmod", "version": "1.0"}',
      'assets/zmod/lang/en_us.json': '{"item.z": "Item Z"}',
    });
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  Future<ModTranslationController> pumpPage(WidgetTester tester) async {
    final settingsController = SettingsController(
      repository: InMemorySettingsRepository(),
      apiKeyStore: InMemoryApiKeyStore(),
    );
    await settingsController.load();
    await settingsController.setApiKey(LlmProvider.openai, 'test-key');

    final modController = ModTranslationController(
      settingsController: settingsController,
      orchestrator: ModTranslationOrchestrator(
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
        child: MaterialApp(home: ModTranslationPage(controller: modController)),
      ),
    );
    await tester.pumpAndSettle();

    return modController;
  }

  testWidgets('未選択→スキャン完了→翻訳完了の状態遷移と、テーブルのチェックボックス・検索が機能する', (tester) async {
    final controller = await pumpPage(tester);

    expect(find.text('未選択'), findsOneWidget);

    // ディレクトリ未選択の間はスキャンボタンが無効。
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

    // スキャンボタンが有効になったことを確認したうえで、実ファイル I/O
    // (dart:io)を伴うためコントローラーを直接呼び出して結果を検証する
    // (fake-async 環境の pump は実 I/O の完了を待てないため)。
    final scanButtonAfter = tester.widget<ElevatedButton>(
      find.byKey(const Key('scanButton')),
    );
    expect(scanButtonAfter.onPressed, isNotNull);

    await tester.runAsync(() => controller.scan());
    await tester.pumpAndSettle();

    expect(find.text('スキャン完了'), findsOneWidget);
    expect(find.byKey(const Key('modRow_moda')), findsOneWidget);
    expect(find.byKey(const Key('modRow_zmod')), findsOneWidget);
    expect(controller.selectedModIds, {'moda', 'zmod'});

    // 部分一致検索: "zmod" で絞り込む。
    await tester.enterText(find.byKey(const Key('searchField')), 'zmod');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('modRow_moda')), findsNothing);
    expect(find.byKey(const Key('modRow_zmod')), findsOneWidget);

    await tester.enterText(find.byKey(const Key('searchField')), '');
    await tester.pumpAndSettle();

    // チェックボックス列: zmod の選択を解除する。
    await tester.tap(find.byKey(const Key('modRow_zmod')));
    await tester.pumpAndSettle();
    expect(controller.selectedModIds, {'moda'});

    final translateButtonAfter = tester.widget<ElevatedButton>(
      find.byKey(const Key('translateButton')),
    );
    expect(translateButtonAfter.onPressed, isNotNull);

    await tester.runAsync(() => controller.translate());
    await tester.pumpAndSettle();

    expect(find.text('完了'), findsOneWidget);
    expect(find.byKey(const Key('translationResultSummary')), findsOneWidget);
    expect(controller.lastResult!.translationResult.translatedModIds, ['moda']);
  });
}
