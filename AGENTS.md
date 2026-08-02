# 開発規約

## 基本方針

- このプロジェクトは Flutter / Dart で実装する Windows デスクトップアプリケーションです。
- すべての説明文、仕様書、コメント、テスト名は原則として日本語で記述します。外部 API の名称やコード上の識別子は英語を使用します。
- 仕様駆動開発を徹底します。実装開始前に `docs/specs/` の対応仕様と受け入れ条件を確認し、仕様がなければ先に追加します。
- 旧 `MinecraftModsLocalizer` は参照実装です。振る舞いを移す場合は、対応する旧実装と仕様を確認してから Flutter 側に再設計します。

## 変更手順

1. `docs/specs/` に目的、対象外、受け入れ条件を記述する。
2. 受け入れ条件を検証するテストを追加または更新する。
3. Flutter の UI、ドメイン、インフラを分離して実装する。
4. `flutter format .`、`flutter analyze`、`flutter test` を実行する。
5. Windows に影響する変更では `flutter build windows --release` で実行形式を確認する。

## 構成

- `lib/`: アプリケーションコード。機能が増えたら `features/`、`domain/`、`infrastructure/` を責務ごとに分ける。
- `test/`: ユニットテストとウィジェットテスト。仕様の受け入れ条件に対応させる。
- `docs/specs/`: このアプリの正本となる仕様書。
- `windows/`: Flutter が生成・管理する Windows ランナー設定。実行ファイル名は `VillagerTranslator.exe` を維持する。
- `.github/workflows/`: CI/CD 定義。

## ドメイン上の制約

- OpenAI などの API キー、ログ、翻訳対象の個人ファイルをコミットしない。
- Minecraft の JAR、JSON、LANG、SNBT を扱う際は、文字コード、元データ保全、途中失敗時の復元を受け入れ条件に含める。
- 翻訳 API は差し替え可能なアダプター境界の内側に閉じ込める。
- 長時間の翻訳処理は進捗表示、キャンセル、部分成功の扱いを仕様に含める。

## 検証コマンド

```powershell
flutter format .
flutter analyze
flutter test
flutter build windows --release
```