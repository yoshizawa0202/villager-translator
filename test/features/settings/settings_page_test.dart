import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
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

  testWidgets('設定変更を保存すると、保存状態インジケーターの表示が更新される(#9)', (tester) async {
    final controller = await pumpSettingsPage(tester);

    expect(find.text('変更内容は入力するたびに自動的に保存されます'), findsOneWidget);

    await controller.updateTranslation(
      (s) => s.copyWith(resourcePackName: 'Changed'),
    );
    await tester.pump();

    expect(find.text('変更内容は入力するたびに自動的に保存されます'), findsNothing);
    expect(find.textContaining('保存しました'), findsOneWidget);
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
}
