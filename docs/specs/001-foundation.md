# 001: Flutter Windows 基盤

## 目的

`MinecraftModsLocalizer` の後継として、Windows で起動できる Flutter ベースの `VillagerTranslator.exe` を確立する。後続の翻訳機能は、この基盤と仕様駆動開発の手順に従って追加する。

## 対象範囲

- Flutter の Windows デスクトッププロジェクトを構成する。
- アプリケーション名を Villager Translator、実行ファイル名を `VillagerTranslator.exe` とする。
- 最低限の起動画面で、Minecraft MOD 翻訳アプリであることと Windows デスクトップ版であることを表示する。
- GitHub Actions で解析、テスト、Windows Release ビルドを実行する。
- `v*` タグに対して Windows 配布バンドルを GitHub Release に添付する。

## 対象外

- MOD、クエスト、Patchouli の実際の検出と翻訳。
- API キーの保存や LLM 接続。
- インストーラー署名と自動更新。

## 受け入れ条件

1. `flutter analyze` が成功する。
2. `flutter test` が成功し、初期画面の主要文言を検証する。
3. `flutter build windows --release` が成功し、`build/windows/x64/runner/Release/VillagerTranslator.exe` を生成する。
4. プルリクエストと `main` への push で、GitHub Actions が解析、テスト、Windows ビルドを実行する。
5. `v*` タグで、実行ファイルと必要な DLL・データを含む zip を GitHub Release に公開する。

## 移行上の判断

旧アプリの翻訳機能と画面は一括移植しない。各機能を仕様書、テスト、実装の順に小さく移行し、ファイル破損や API キー漏えいのリスクを抑える。