import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:villager_translator/features/instance_list/instance_list_page.dart';
import 'package:villager_translator/features/settings/settings_controller.dart';
import 'package:villager_translator/features/settings/settings_page.dart';
import 'package:villager_translator/features/shell/main_shell_page.dart';
import 'package:villager_translator/main.dart';

import 'test_support/fake_windows_environment.dart';
import 'test_support/in_memory_api_key_store.dart';
import 'test_support/in_memory_settings_repository.dart';

Future<SettingsController> _buildTestController() async {
  final controller = SettingsController(
    repository: InMemorySettingsRepository(),
    apiKeyStore: InMemoryApiKeyStore(),
  );
  await controller.load();
  return controller;
}

void main() {
  testWidgets('起動時ホーム画面が Minecraft インスタンス一覧になっている(011 AC-13)', (tester) async {
    final controller = await _buildTestController();

    await tester.pumpWidget(
      VillagerTranslatorApp(
        settingsController: controller,
        instanceListEnvironment: const FakeWindowsEnvironment(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(InstanceListPage), findsOneWidget);
    expect(find.text('Minecraft インスタンス'), findsOneWidget);
  });

  testWidgets('歯車アイコンから設定画面へ遷移できる', (tester) async {
    final controller = await _buildTestController();

    await tester.pumpWidget(
      VillagerTranslatorApp(
        settingsController: controller,
        instanceListEnvironment: const FakeWindowsEnvironment(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('instanceListSettingsButton')));
    await tester.pumpAndSettle();

    expect(find.byType(SettingsPage), findsOneWidget);
  });

  testWidgets('一覧画面から従来の 4 タブ統合シェルを開ける(011 §17、AC-22)', (tester) async {
    final controller = await _buildTestController();

    await tester.pumpWidget(
      VillagerTranslatorApp(
        settingsController: controller,
        instanceListEnvironment: const FakeWindowsEnvironment(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('openManualProfileButton')));
    await tester.pumpAndSettle();

    expect(find.byType(MainShellPage), findsOneWidget);
    expect(find.byKey(const Key('mainShellTabBar')), findsOneWidget);
    expect(find.text('MOD'), findsOneWidget);
    expect(find.text('クエスト'), findsOneWidget);
    expect(find.text('ガイドブック'), findsOneWidget);
    expect(find.text('カスタムファイル'), findsOneWidget);
  });
}
