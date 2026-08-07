# GitHub Actions ワークフロー一覧

`.github/workflows/` 配下の各ワークフローの目的・トリガー・処理内容をまとめる。ワークフロー本体を変更した際は、このドキュメントも合わせて更新する。

## 一覧

| ファイル | 名前 | 役割 |
|---|---|---|
| [`ci.yml`](../.github/workflows/ci.yml) | Windows CI/CD | 解析・テスト・Windows ビルド・リリース |
| [`claude.yml`](../.github/workflows/claude.yml) | Claude Code | `@claude` メンションへの対話的な応答 |
| [`claude-code-review.yml`](../.github/workflows/claude-code-review.yml) | Claude Code Review | プルリクエストの自動コードレビュー |

## `ci.yml`(Windows CI/CD)

### トリガー

- `main` への push / `main` 向け pull request
- `v*` タグの push
- `workflow_dispatch`(手動実行)

### `verify` ジョブ(`windows-latest`)

1. リポジトリを取得
2. `subosito/flutter-action@v2` で Flutter(stable チャンネル)をセットアップ
3. `flutter pub get`
4. `flutter analyze`
5. `flutter test`
6. `flutter build windows --release`
7. `build/windows/x64/runner/Release/*` を zip 化(`VillagerTranslator-windows-x64.zip`)
8. 成果物を Actions のアーティファクトとして保存

Windows 実機ビルド(`flutter build windows --release`)を伴うため `windows-latest` 上で実行する。`AGENTS.md` の検証コマンドと対応関係にある。

### `release` ジョブ(`ubuntu-latest`)

- `refs/tags/v*` への push のときのみ実行(`verify` に依存)。
- `verify` が生成したアーティファクトをダウンロードし、`softprops/action-gh-release@v2` で GitHub Release を作成、zip を添付する。
- `permissions: contents: write` が必要(Release 作成のため)。

## `claude.yml`(Claude Code)

### トリガー

- issue コメント、PR レビューコメント、PR レビュー本文、issue 本文/タイトルのいずれかに `@claude` が含まれる場合(`if` 条件で判定)。

### 処理内容

- `anthropics/claude-code-action@v1` を使い、メンションした内容に応じて Claude Code が対話的に応答する。
- `additional_permissions: actions: read` により、PR 上の CI 結果を Claude が参照できる。
- `claude_args` の `--append-system-prompt` で、特に指示がない限り日本語で応答するよう指示(`AGENTS.md` の言語方針に対応)。コードや識別子名は英語のまま維持する指示も含む。
- 必要な secret: `CLAUDE_CODE_OAUTH_TOKEN`。

## `claude-code-review.yml`(Claude Code Review)

### トリガー

- pull request の `opened` / `synchronize` / `ready_for_review` / `reopened`。
- `paths` フィルタにより、`lib/**`・`test/**`・`docs/specs/**`・`pubspec.yaml`・`pubspec.lock` に変更がある PR のみを対象とする(ワークフロー自体やドキュメント全般の変更ではレビューを起動しない)。

### 処理内容(`ubuntu-latest`)

1. リポジトリを取得
2. `subosito/flutter-action@v2` で Flutter(stable チャンネル)をセットアップ
3. `flutter pub get`
4. `anthropics/claude-code-action@v1` + `code-review@claude-code-plugins` プラグインでコードレビューを実行

### レビュー中の Flutter SDK 利用

レビューの妥当性検証(`flutter test` / `flutter analyze` などの実行)ができるよう、事前に Flutter をセットアップした上で、`claude_args` に以下を指定している。

```
--allowed-tools "Bash(flutter *),Bash(dart *)"
```

- `ubuntu-latest` 上で動作するため、`flutter build windows --release` は実行できない(Windows 向けビルド確認は `ci.yml` に委ねる)。
- レビューの要約・指摘コメントは `--append-system-prompt` により日本語で出力させる。コードや識別子名(英語)は変更させない。

### 必要な権限・secret

- `permissions`: `contents: read` / `pull-requests: write` / `issues: write` / `id-token: write`
- 必要な secret: `CLAUDE_CODE_OAUTH_TOKEN`

## 共通の注意点

- いずれのワークフローも `CLAUDE_CODE_OAUTH_TOKEN` を repository secret として設定しておく必要がある。
- `claude.yml` と `claude-code-review.yml` の日本語応答方針は `AGENTS.md` の「すべての説明文...は原則として日本語で記述します」という基本方針に対応させている。方針を変更する場合は `AGENTS.md` との整合性も確認する。
- ワークフローの `paths` / `on` 条件を変更する場合、意図しない PR でレビューや CI が起動(または起動しなくなる)しないか確認する。
