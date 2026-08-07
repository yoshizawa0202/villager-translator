import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:villager_translator/domain/common/translation_progress.dart';
import 'package:villager_translator/features/shell/widgets/translation_progress_panel.dart';

Future<void> _pump(
  WidgetTester tester, {
  OverallProgress? overallProgress,
  ChunkProgress? singleFileProgress,
  String? currentItemName,
  VoidCallback? onCancel,
  bool isCancelling = false,
}) {
  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: TranslationProgressPanel(
          overallProgress: overallProgress,
          singleFileProgress: singleFileProgress,
          currentItemName: currentItemName,
          onCancel: onCancel,
          isCancelling: isCancelling,
        ),
      ),
    ),
  );
}

void main() {
  group('TranslationProgressPanel', () {
    testWidgets('全体進捗が未設定(翻訳未開始)の場合は何も表示しない', (tester) async {
      await _pump(tester);

      expect(find.byKey(const Key('translationProgressPanel')), findsNothing);
    });

    testWidgets('全体進捗が設定されている場合、プログレスバーとテキストを表示する(受け入れ条件4a)', (tester) async {
      await _pump(
        tester,
        overallProgress: const OverallProgress(
          completedItems: 1,
          totalItems: 4,
        ),
      );

      expect(find.byKey(const Key('translationProgressPanel')), findsOneWidget);
      final bar = tester.widget<LinearProgressIndicator>(
        find.byKey(const Key('overallProgressBar')),
      );
      expect(bar.value, closeTo(0.25, 0.0001));
      expect(find.text('1 / 4 件完了 (25%)'), findsOneWidget);
    });

    testWidgets('現在処理中の対象名が設定されている場合、「翻訳中: 」表示を行う(受け入れ条件4b)', (tester) async {
      await _pump(
        tester,
        overallProgress: const OverallProgress(
          completedItems: 0,
          totalItems: 2,
        ),
        currentItemName: 'Example Mod',
      );

      expect(find.text('翻訳中: Example Mod'), findsOneWidget);
    });

    testWidgets('現在処理中の対象名が未設定の場合、「翻訳中: 」表示を行わない', (tester) async {
      await _pump(
        tester,
        overallProgress: const OverallProgress(
          completedItems: 0,
          totalItems: 2,
        ),
      );

      expect(find.byKey(const Key('currentItemLabel')), findsNothing);
    });

    testWidgets('単一ファイル進捗が設定されている場合、専用のプログレスバーを表示する', (tester) async {
      await _pump(
        tester,
        overallProgress: const OverallProgress(
          completedItems: 0,
          totalItems: 1,
        ),
        singleFileProgress: const ChunkProgress(
          completedChunks: 2,
          totalChunks: 5,
        ),
      );

      final bar = tester.widget<LinearProgressIndicator>(
        find.byKey(const Key('singleFileProgressBar')),
      );
      expect(bar.value, closeTo(0.4, 0.0001));
      expect(find.text('現在のファイル: 2 / 5 チャンク完了 (40%)'), findsOneWidget);
    });

    testWidgets('単一ファイル進捗が未設定の場合、専用のプログレスバーを表示しない', (tester) async {
      await _pump(
        tester,
        overallProgress: const OverallProgress(
          completedItems: 0,
          totalItems: 1,
        ),
      );

      expect(find.byKey(const Key('singleFileProgressBar')), findsNothing);
    });

    testWidgets('onCancel が渡されていない場合、キャンセルボタンを表示しない', (tester) async {
      await _pump(
        tester,
        overallProgress: const OverallProgress(
          completedItems: 0,
          totalItems: 1,
        ),
      );

      expect(find.byKey(const Key('cancelTranslationButton')), findsNothing);
    });

    testWidgets(
      'onCancel が渡されている場合、プログレスバー付近にキャンセルボタンを表示し、押下で呼び出される(Issue #7)',
      (tester) async {
        var cancelled = false;
        await _pump(
          tester,
          overallProgress: const OverallProgress(
            completedItems: 0,
            totalItems: 1,
          ),
          onCancel: () => cancelled = true,
        );

        expect(
          find.byKey(const Key('cancelTranslationButton')),
          findsOneWidget,
        );
        expect(find.text('キャンセル'), findsOneWidget);

        await tester.tap(find.byKey(const Key('cancelTranslationButton')));
        await tester.pump();

        expect(cancelled, isTrue);
      },
    );

    testWidgets('isCancelling が true の場合、ボタンを無効化し「キャンセル中...」と表示する(Issue #7)', (
      tester,
    ) async {
      var cancelled = false;
      await _pump(
        tester,
        overallProgress: const OverallProgress(
          completedItems: 0,
          totalItems: 1,
        ),
        onCancel: () => cancelled = true,
        isCancelling: true,
      );

      expect(find.text('キャンセル中...'), findsOneWidget);

      final button = tester.widget<OutlinedButton>(
        find.byKey(const Key('cancelTranslationButton')),
      );
      expect(button.onPressed, isNull);

      await tester.tap(
        find.byKey(const Key('cancelTranslationButton')),
        warnIfMissed: false,
      );
      await tester.pump();
      expect(cancelled, isFalse);
    });
  });
}
