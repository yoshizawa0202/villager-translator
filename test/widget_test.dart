import 'package:flutter_test/flutter_test.dart';

import 'package:villager_translator/main.dart';

void main() {
  testWidgets('初期画面にプロジェクトの目的を表示する', (tester) async {
    await tester.pumpWidget(const VillagerTranslatorApp());

    expect(find.text('Minecraft MOD 翻訳'), findsOneWidget);
    expect(find.text('Windows デスクトップ版'), findsOneWidget);
  });
}
