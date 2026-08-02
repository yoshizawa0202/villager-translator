import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:villager_translator/features/settings/settings_controller.dart';
import 'package:villager_translator/features/settings/widgets/language_management_dialog.dart';

import '../../test_support/in_memory_api_key_store.dart';
import '../../test_support/in_memory_settings_repository.dart';

void main() {
  testWidgets(
    '既定言語は削除不可、カスタム言語は追加・削除できる (AC8)',
    (tester) async {
      final controller = SettingsController(
        repository: InMemorySettingsRepository(),
        apiKeyStore: InMemoryApiKeyStore(),
      );
      await controller.load();

      await tester.pumpWidget(
        ChangeNotifierProvider<SettingsController>.value(
          value: controller,
          child: const MaterialApp(
            home: Scaffold(body: LanguageManagementButton()),
          ),
        ),
      );

      await tester.tap(find.byKey(const Key('openLanguageManagementButton')));
      await tester.pumpAndSettle();

      // 既定言語(例: 日本語)には削除ボタンがなく、ロックアイコンが表示される。
      expect(find.byKey(const Key('removeLanguage_ja_jp')), findsNothing);
      expect(
        find.descendant(
          of: find.byKey(const Key('language_ja_jp')),
          matching: find.byIcon(Icons.lock),
        ),
        findsOneWidget,
      );

      // カスタム言語を追加する。
      await tester.enterText(
        find.byKey(const Key('newLanguageIdField')),
        'xx_xx',
      );
      await tester.enterText(
        find.byKey(const Key('newLanguageNameField')),
        'Xx語',
      );
      // フォーカスが残ったままだとカーソル点滅アニメーションが継続し、
      // pumpAndSettle がフレームの発生を待ち続けてしまうため明示的に外す。
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump();
      await tester.ensureVisible(find.byKey(const Key('addLanguageButton')));
      await tester.tap(find.byKey(const Key('addLanguageButton')));
      await tester.pumpAndSettle();

      expect(
        controller.settings.translation.customLanguages.map((l) => l.id),
        contains('xx_xx'),
      );
      await tester.scrollUntilVisible(
        find.byKey(const Key('language_xx_xx')),
        100,
        scrollable: find.descendant(
          of: find.byKey(const Key('languageList')),
          matching: find.byType(Scrollable),
        ),
      );
      expect(find.byKey(const Key('language_xx_xx')), findsOneWidget);
      expect(find.byKey(const Key('removeLanguage_xx_xx')), findsOneWidget);

      // カスタム言語を削除する。
      await controller.removeCustomLanguage('xx_xx');
      await tester.pump();

      expect(find.byKey(const Key('language_xx_xx')), findsNothing);
      expect(controller.settings.translation.customLanguages, isEmpty);
    },
  );
}
