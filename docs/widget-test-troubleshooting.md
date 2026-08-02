# Widget Test Troubleshooting

Flutter の widget test で `flutter test` が終わらなくなる事象について、今回の調査結果をまとめる。

## 症状

- `flutter test` 実行中に特定の widget test が完了しない。
- `pumpAndSettle()` が原因に見えても、実際にはその前の `await` で停止していることがある。
- 今回は設定画面テストで `SettingsController.load()` の途中から進まなくなった。

## 今回の直接原因

widget test の fake async 環境で、実ファイル I/O を行う `SettingsRepository` をそのまま使っていた。

具体的には、以下のような経路で `dart:io` の `File.exists()` や `File.readAsString()` を await していた。

1. widget test が `SettingsController.load()` を呼ぶ
2. `SettingsController.load()` が `SettingsRepository.load()` を呼ぶ
3. `SettingsRepository.load()` が `File.exists()` などの実 I/O を行う

この構成だと widget test では待機が解消されず、テストが停止したように見える。

## 切り分け手順

### 1. 停止位置を print で特定する

`pumpAndSettle()` が怪しく見える場合でも、その前後に `print()` を置いて本当にどこで止まっているかを確認する。

今回のケースでは、`pumpAndSettle()` ではなく `SettingsController.load()` の中で停止していた。

### 2. widget test か通常 test かを分けて考える

- 通常の `test()` では実ファイル I/O を使っても問題になりにくい
- `testWidgets()` では fake async とフレーム待機が絡むため、実 I/O 依存をそのまま持ち込まない方が安全

### 3. `tester.runAsync()` は応急処置に留める

`tester.runAsync()` で回避できることはあるが、永続化やロードが複数箇所に散るとテスト全体が不安定になる。
根本対処は widget test から実 I/O 依存を外すこと。

## 再発防止策

### 1. widget test では in-memory なテストダブルを使う

今回追加した `InMemorySettingsRepository` を使い、設定のロード・保存をメモリ内で完結させる。

対象:

- [test/test_support/in_memory_settings_repository.dart](test/test_support/in_memory_settings_repository.dart)
- [test/features/settings/settings_page_test.dart](test/features/settings/settings_page_test.dart)
- [test/features/settings/language_management_dialog_test.dart](test/features/settings/language_management_dialog_test.dart)
- [test/widget_test.dart](test/widget_test.dart)

方針:

- widget test: 実ファイル I/O を避ける
- repository 自体の検証: 通常の `test()` で実ファイル I/O を検証する

この分離により、UI テストは UI の振る舞いだけを見て、永続化の詳細は repository テストに閉じ込められる。

### 2. `pumpAndSettle()` を無条件に信じない

`pumpAndSettle()` が終わらない原因は 2 系統ある。

- その前段の future が解決していない
- 継続的にフレームを発生させる要素が残っている

今回の設定画面テストでは、後者として TextField のフォーカスが残り、カーソル点滅でフレームが出続ける箇所もあった。

必要に応じて以下を使う。

- `FocusManager.instance.primaryFocus?.unfocus();`
- `await tester.pump();`
- 長い `pumpAndSettle()` の代わりに、必要最小限の `pump()` を使う

## 実装上の判断

今回の修正では、production code 側に widget test 専用の分岐は入れず、テスト側の依存注入で解決した。

理由:

- 問題はアプリ本体の仕様ではなく、widget test の実行条件に起因していた
- repository の本来の責務であるファイル永続化は維持したかった
- UI テストを実 I/O から切り離した方が速度と安定性の両面で有利

## 今後の指針

- `testWidgets()` で controller や service を組み立てるときは、実ファイル・実ネットワーク・プラットフォームチャネル依存がないか先に確認する
- 永続化や外部アクセスを伴う依存は、可能なら in-memory の fake / stub を `test_support/` に置く
- ハング調査では、広く疑うより「最後に出た print」と「その直後の await」を見て停止位置を固定する