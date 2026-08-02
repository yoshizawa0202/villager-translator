import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:villager_translator/features/settings/settings_controller.dart';
import 'package:villager_translator/features/settings/settings_page.dart';
import 'package:villager_translator/main.dart';

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
  testWidgets('初期画面にプロジェクトの目的を表示する', (tester) async {
    final controller = await _buildTestController();

    await tester.pumpWidget(
      VillagerTranslatorApp(settingsController: controller),
    );

    expect(find.text('Minecraft MOD 翻訳'), findsOneWidget);
    expect(find.text('Windows デスクトップ版'), findsOneWidget);
  });

  testWidgets('歯車アイコンから設定画面へ遷移できる', (tester) async {
    final controller = await _buildTestController();

    await tester.pumpWidget(
      VillagerTranslatorApp(settingsController: controller),
    );
    await tester.tap(find.byKey(const Key('openSettingsButton')));
    await tester.pumpAndSettle();

    expect(find.byType(SettingsPage), findsOneWidget);
  });
}
