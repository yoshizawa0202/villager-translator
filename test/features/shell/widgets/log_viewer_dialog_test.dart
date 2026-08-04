import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:villager_translator/features/shell/widgets/log_viewer_dialog.dart';
import 'package:villager_translator/infrastructure/common/session_logger.dart';

void main() {
  testWidgets('翻訳中(isBusy: true)は全件、アイドル時(isBusy: false)は要約(エラー・節目のみ)を表示する', (
    tester,
  ) async {
    final logger = SessionLogger();
    logger.log(LogLevel.info, 'scan', '通常メッセージ');
    logger.log(LogLevel.info, 'translate', '節目メッセージ', isMilestone: true);
    logger.log(LogLevel.error, 'translate', 'エラーメッセージ');

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            return Column(
              children: [
                ElevatedButton(
                  key: const Key('openBusy'),
                  onPressed: () => LogViewerDialog.show(
                    context,
                    logger: logger,
                    isBusy: true,
                  ),
                  child: const Text('busy'),
                ),
                ElevatedButton(
                  key: const Key('openIdle'),
                  onPressed: () => LogViewerDialog.show(
                    context,
                    logger: logger,
                    isBusy: false,
                  ),
                  child: const Text('idle'),
                ),
              ],
            );
          },
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('openBusy')));
    await tester.pumpAndSettle();
    expect(find.text('通常メッセージ'), findsOneWidget);
    expect(find.text('節目メッセージ'), findsOneWidget);
    expect(find.text('エラーメッセージ'), findsOneWidget);
    await tester.tap(find.text('閉じる'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('openIdle')));
    await tester.pumpAndSettle();
    expect(find.text('通常メッセージ'), findsNothing);
    expect(find.text('節目メッセージ'), findsOneWidget);
    expect(find.text('エラーメッセージ'), findsOneWidget);
  });

  testWidgets('ログが1件もない場合は空状態のメッセージを表示する', (tester) async {
    final logger = SessionLogger();

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () =>
                LogViewerDialog.show(context, logger: logger, isBusy: false),
            child: const Text('open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('ログはありません'), findsOneWidget);
  });
}
