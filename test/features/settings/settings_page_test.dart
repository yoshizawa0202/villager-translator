import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:villager_translator/domain/llm/llm_provider.dart';
import 'package:villager_translator/features/settings/settings_controller.dart';
import 'package:villager_translator/features/settings/settings_page.dart';

import '../../test_support/in_memory_api_key_store.dart';
import '../../test_support/in_memory_settings_repository.dart';

Future<SettingsController> pumpSettingsPage(WidgetTester tester) async {
  final controller = SettingsController(
    repository: InMemorySettingsRepository(),
    apiKeyStore: InMemoryApiKeyStore(),
  );
  await controller.load();

  await tester.pumpWidget(
    ChangeNotifierProvider<SettingsController>.value(
      value: controller,
      child: const MaterialApp(home: SettingsPage()),
    ),
  );
  await tester.pumpAndSettle();

  return controller;
}

void main() {
  testWidgets('プロバイダーを切り替えると API キー欄のラベルが切り替わる (AC1)', (tester) async {
    await pumpSettingsPage(tester);

    expect(find.text('OpenAI API キー'), findsOneWidget);

    await tester.ensureVisible(find.byKey(const Key('providerSelector')));
    await tester.tap(find.byKey(const Key('providerSelector')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Anthropic').last);
    await tester.pumpAndSettle();

    expect(find.text('Anthropic API キー'), findsOneWidget);
  });

  testWidgets('モデルで「カスタム」を選ぶと自由入力欄が表示され、空欄はエラーになる (AC2)', (tester) async {
    await pumpSettingsPage(tester);

    expect(find.byKey(const Key('customModelField')), findsNothing);

    await tester.ensureVisible(find.byKey(const Key('modelSelector')));
    await tester.tap(find.byKey(const Key('modelSelector')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('カスタム').last);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('customModelField')), findsOneWidget);

    await tester.enterText(find.byKey(const Key('customModelField')), 'x');
    await tester.enterText(find.byKey(const Key('customModelField')), '');
    // フォーカスが残ったままだとカーソル点滅アニメーションが継続し、
    // pumpAndSettle がフレームの発生を待ち続けてしまうため明示的に外す。
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();

    expect(find.text('カスタムモデル名を入力してください'), findsOneWidget);
  });

  testWidgets('API キー入力欄の表示/非表示切替アイコンでマスク状態が反転する (AC4)', (tester) async {
    await pumpSettingsPage(tester);

    await tester.ensureVisible(find.byKey(const Key('apiKeyField')));
    final fieldBefore = tester.widget<TextField>(
      find.descendant(
        of: find.byKey(const Key('apiKeyField')),
        matching: find.byType(TextField),
      ),
    );
    expect(fieldBefore.obscureText, isTrue);

    await tester.tap(find.byKey(const Key('apiKeyVisibilityToggle')));
    await tester.pumpAndSettle();

    final fieldAfter = tester.widget<TextField>(
      find.descendant(
        of: find.byKey(const Key('apiKeyField')),
        matching: find.byType(TextField),
      ),
    );
    expect(fieldAfter.obscureText, isFalse);
  });

  testWidgets('プロンプト編集欄に単一波括弧のプレースホルダーのみが説明表示される (AC9)', (tester) async {
    await pumpSettingsPage(tester);

    await tester.ensureVisible(find.byKey(const Key('systemPromptField')));

    expect(find.textContaining('{language}'), findsWidgets);
    expect(find.textContaining('{{language}}'), findsNothing);
    expect(find.textContaining('{{content}}'), findsNothing);
  });

  testWidgets('項目を変更しただけでは永続化されず、保存ボタンを押すと反映される(#9、#11)', (tester) async {
    final repository = InMemorySettingsRepository();
    final controller = SettingsController(
      repository: repository,
      apiKeyStore: InMemoryApiKeyStore(),
    );
    await controller.load();

    await tester.pumpWidget(
      ChangeNotifierProvider<SettingsController>.value(
        value: controller,
        child: const MaterialApp(home: SettingsPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('変更後に「保存」ボタンを押すと反映されます'), findsOneWidget);

    await controller.updateTranslation(
      (s) => s.copyWith(resourcePackName: 'Changed'),
    );
    await tester.pump();

    expect(find.textContaining('未保存の変更があります'), findsOneWidget);
    final beforeSave = await repository.load();
    expect(beforeSave.translation.resourcePackName, 'VillagerTranslator');

    await tester.tap(find.byKey(const Key('saveSettingsButton')));
    await tester.pumpAndSettle();

    expect(find.textContaining('未保存の変更があります'), findsNothing);
    expect(find.textContaining('保存しました'), findsOneWidget);
    final afterSave = await repository.load();
    expect(afterSave.translation.resourcePackName, 'Changed');
  });

  testWidgets('テキスト欄を編集した直後に Enter を押さず保存ボタンを押しても、入力値が破棄されずに保存される', (
    tester,
  ) async {
    final repository = InMemorySettingsRepository();
    final controller = SettingsController(
      repository: repository,
      apiKeyStore: InMemoryApiKeyStore(),
    );
    await controller.load();

    await tester.pumpWidget(
      ChangeNotifierProvider<SettingsController>.value(
        value: controller,
        child: const MaterialApp(home: SettingsPage()),
      ),
    );
    await tester.pumpAndSettle();

    final scrollable = find.ancestor(
      of: find.byKey(const Key('apiKeyField')),
      matching: find.byType(Scrollable),
    );
    await tester.dragUntilVisible(
      find.byKey(const Key('resourcePackNameField')),
      scrollable,
      const Offset(0, -200),
    );
    await tester.enterText(
      find.byKey(const Key('resourcePackNameField')),
      'CustomPackName',
    );

    // Enter 確定やフォーカスを外す操作を挟まず、直接保存ボタンを押す。
    await tester.tap(find.byKey(const Key('saveSettingsButton')));
    await tester.pumpAndSettle();

    expect(
      find.text('CustomPackName'),
      findsOneWidget,
      reason: '保存後も入力した値が画面に残っていること',
    );
    final afterSave = await repository.load();
    expect(afterSave.translation.resourcePackName, 'CustomPackName');
  });

  testWidgets('未保存の変更がある状態で閉じようとすると警告ダイアログが表示される', (tester) async {
    final controller = SettingsController(
      repository: InMemorySettingsRepository(),
      apiKeyStore: InMemoryApiKeyStore(),
    );
    await controller.load();

    await tester.pumpWidget(
      ChangeNotifierProvider<SettingsController>.value(
        value: controller,
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const SettingsPage()),
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await controller.updateTranslation(
      (s) => s.copyWith(resourcePackName: 'Changed'),
    );
    await tester.pump();

    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(find.text('保存されていない変更があります'), findsOneWidget);
    // 設定画面はまだ閉じていない。
    expect(find.byKey(const Key('saveSettingsButton')), findsOneWidget);

    await tester.tap(find.byKey(const Key('discardChangesCancelButton')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('saveSettingsButton')), findsOneWidget);
    expect(
      controller.settings.translation.resourcePackName,
      'Changed',
      reason: 'キャンセルではドラフトは破棄されない',
    );

    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('discardChangesConfirmButton')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('saveSettingsButton')), findsNothing);
    expect(
      controller.settings.translation.resourcePackName,
      'VillagerTranslator',
    );
  });

  testWidgets('未保存の変更がなければ警告なしに閉じられる', (tester) async {
    final controller = SettingsController(
      repository: InMemorySettingsRepository(),
      apiKeyStore: InMemoryApiKeyStore(),
    );
    await controller.load();

    await tester.pumpWidget(
      ChangeNotifierProvider<SettingsController>.value(
        value: controller,
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const SettingsPage()),
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(find.text('保存されていない変更があります'), findsNothing);
    expect(find.byKey(const Key('saveSettingsButton')), findsNothing);
  });

  testWidgets('翻訳実行中に設定画面を開くと注意書きが表示される(#9)', (tester) async {
    final controller = SettingsController(
      repository: InMemorySettingsRepository(),
      apiKeyStore: InMemoryApiKeyStore(),
    );
    await controller.load();

    await tester.pumpWidget(
      ChangeNotifierProvider<SettingsController>.value(
        value: controller,
        child: const MaterialApp(
          home: SettingsPage(isTranslationRunning: true),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('translationRunningNotice')), findsOneWidget);
  });

  testWidgets('翻訳実行中でなければ注意書きは表示されない(#9)', (tester) async {
    await pumpSettingsPage(tester);

    expect(find.byKey(const Key('translationRunningNotice')), findsNothing);
  });

  testWidgets('「デフォルトに戻す」で翻訳設定が初期値に戻る (AC5)', (tester) async {
    final controller = await pumpSettingsPage(tester);
    await controller.updateTranslation(
      (s) => s.copyWith(resourcePackName: 'Changed'),
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('resetToDefaultsButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('戻す'));
    await tester.pumpAndSettle();

    expect(
      controller.settings.translation.resourcePackName,
      'VillagerTranslator',
    );
  });

  testWidgets('OpenAI 以外のプロバイダーで「デフォルトに戻す」を押しても、選択中プロバイダーと'
      'その API キー欄の表示が保持される', (tester) async {
    final apiKeyStore = InMemoryApiKeyStore();
    final controller = SettingsController(
      repository: InMemorySettingsRepository(),
      apiKeyStore: apiKeyStore,
    );
    await controller.load();
    await controller.setProvider(LlmProvider.anthropic);
    await controller.setApiKey(LlmProvider.anthropic, 'secret-key');
    await controller.save();

    await tester.pumpWidget(
      ChangeNotifierProvider<SettingsController>.value(
        value: controller,
        child: const MaterialApp(home: SettingsPage()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('resetToDefaultsButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('戻す'));
    await tester.pumpAndSettle();

    expect(controller.settings.llm.provider, LlmProvider.anthropic);
    expect(controller.apiKeyFor(LlmProvider.anthropic), 'secret-key');
    expect(await apiKeyStore.read(LlmProvider.anthropic), 'secret-key');

    final apiKeyFieldText = tester.widget<TextField>(
      find.descendant(
        of: find.byKey(const Key('apiKeyField')),
        matching: find.byType(TextField),
      ),
    );
    expect(apiKeyFieldText.controller?.text, 'secret-key');
  });
}
