import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:villager_translator/features/shell/widgets/history_dialog.dart';

/// セッション一覧の取得ロジック(降順ソート・任意ディレクトリ指定・
/// サマリ欠損時の扱い・ログ読み出し)は
/// `test/infrastructure/common/history_repository_test.dart` で網羅済み。
/// ここでは [HistoryDialog] が案内表示・入力欄を正しく提供する骨組みのみを
/// 検証する(実 I/O を伴うウィジェット操作は、このプロジェクトの実行環境では
/// テストランナーが不安定になるため意図的に避ける)。
void main() {
  testWidgets('ディレクトリ未指定で開くと案内メッセージと入力欄を表示する', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => HistoryDialog.show(context),
            child: const Text('open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pump();

    expect(find.text('ディレクトリを指定してください'), findsOneWidget);
    expect(find.byKey(const Key('historyDirectoryField')), findsOneWidget);
    expect(
      find.byKey(const Key('historyBrowseDirectoryButton')),
      findsOneWidget,
    );
  });
}
