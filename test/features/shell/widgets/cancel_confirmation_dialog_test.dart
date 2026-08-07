import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:villager_translator/features/shell/widgets/cancel_confirmation_dialog.dart';

void main() {
  group('CancelConfirmationDialog', () {
    testWidgets('「キャンセルする」を選択すると true を返す(受け入れ条件5a)', (tester) async {
      bool? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                key: const Key('openDialogButton'),
                onPressed: () async {
                  result = await CancelConfirmationDialog.show(context);
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.byKey(const Key('openDialogButton')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('cancelConfirmationDialog')),
        findsOneWidget,
      );
      expect(find.text('翻訳をキャンセルしますか?'), findsOneWidget);

      await tester.tap(
        find.byKey(const Key('cancelConfirmationDialogConfirm')),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('cancelConfirmationDialog')), findsNothing);
      expect(result, isTrue);
    });

    testWidgets('「戻る」を選択すると false を返す(受け入れ条件5a)', (tester) async {
      bool? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                key: const Key('openDialogButton'),
                onPressed: () async {
                  result = await CancelConfirmationDialog.show(context);
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.byKey(const Key('openDialogButton')));
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const Key('cancelConfirmationDialogDismiss')),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('cancelConfirmationDialog')), findsNothing);
      expect(result, isFalse);
    });
  });
}
