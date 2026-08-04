import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:villager_translator/domain/common/translation_summary.dart';
import 'package:villager_translator/features/shell/widgets/translation_completion_dialog.dart';

void main() {
  final summary = TranslationSummary(
    sessionId: 's',
    targetLanguage: 'ja_jp',
    createdAt: DateTime(2026, 8, 4),
    items: const [
      TranslationSummaryItem(
        type: TranslationTargetType.mod,
        id: 'moda',
        displayName: 'Mod A',
        targetLanguage: 'ja_jp',
        success: true,
        translatedKeyCount: 5,
        totalKeyCount: 5,
      ),
      TranslationSummaryItem(
        type: TranslationTargetType.mod,
        id: 'modb',
        displayName: 'Mod B',
        targetLanguage: 'ja_jp',
        success: false,
        translatedKeyCount: 2,
        totalKeyCount: 5,
      ),
    ],
  );

  testWidgets('成功/失敗/合計件数と結果一覧を表示し、検索で絞り込める', (tester) async {
    var showLogTapped = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            return ElevatedButton(
              onPressed: () => TranslationCompletionDialog.show(
                context,
                summary: summary,
                onShowLog: () => showLogTapped = true,
              ),
              child: const Text('open'),
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('completionDialogCounts')), findsOneWidget);
    expect(find.text('成功 1 / 失敗 1 / 合計 2 件'), findsOneWidget);
    expect(find.text('Mod A'), findsOneWidget);
    expect(find.text('Mod B'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('completionDialogSearchField')),
      'moda',
    );
    await tester.pumpAndSettle();

    expect(find.text('Mod A'), findsOneWidget);
    expect(find.text('Mod B'), findsNothing);

    await tester.tap(find.byKey(const Key('completionDialogShowLogButton')));
    await tester.pumpAndSettle();

    expect(showLogTapped, isTrue);
  });
}
