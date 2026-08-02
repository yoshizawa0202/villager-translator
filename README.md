# Villager Translator

Minecraft の MOD、クエスト、Patchouli ガイドブックをローカル環境で翻訳する Windows デスクトップアプリケーションです。旧 `MinecraftModsLocalizer` の機能を Flutter へ段階的に移行・改善します。

## 開発方針

- 技術スタックは Flutter / Dart とし、Windows の実行形式は `VillagerTranslator.exe` とします。
- 実装より先に仕様を確定する仕様駆動開発を採用します。
- 仕様、設計、開発手順、UI の文言は日本語で記述します。
- API キーや個人の Minecraft データはリポジトリへ追加しません。

## 現在の仕様

初期基盤の仕様は [docs/specs/001-foundation.md](docs/specs/001-foundation.md) にあります。機能追加時は、番号付きの仕様書を先に追加または更新し、受け入れ条件を満たすテストと実装を同じ変更に含めます。

移行元の要件は `../MinecraftModsLocalizer/docs/spec.md` を参照してください。新規実装の正本はこのリポジトリ内の `docs/specs/` です。

## 前提条件

- Windows 10/11
- Flutter stable 3.44 以降
- Visual Studio 2022 の「Desktop development with C++」ワークロード
- Git

Flutter SDK を PATH に登録していない場合は、以下のように一時的に設定できます。

```powershell
$env:PATH = "C:\src\flutter\bin;$env:PATH"
flutter doctor
```

## 開発コマンド

```powershell
flutter pub get
flutter analyze
flutter test
flutter run -d windows
```

## Windows 実行ファイルのビルド

```powershell
flutter build windows --release
```

配布対象は `build/windows/x64/runner/Release/` のディレクトリ全体です。`VillagerTranslator.exe` だけではなく、同階層の DLL と `data/` も必要です。

## CI/CD

GitHub Actions は pull request と `main` への push で静的解析・テスト・Windows Release ビルドを実行します。`v*` 形式のタグでは、Windows 配布バンドルを添付した GitHub Release を作成します。

## ライセンス

移行元と同様に MIT License を適用する予定です。ライセンス本文は公開前にこのリポジトリへ追加します。

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
