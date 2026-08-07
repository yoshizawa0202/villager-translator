# 009: 思考量(reasoning effort / extended thinking)の設定

## 目的

`002-settings-and-llm-adapter.md` で扱った LLM 設定に、モデルの「思考量」を追加する。OpenAI の `reasoning_effort`、Anthropic の extended thinking(`thinking.budget_tokens`)、Gemini の `thinkingConfig.thinkingBudget` はいずれもプロバイダー・モデルごとにパラメータ形式(列挙値 vs トークン予算)と対応可否が異なるため、UI・設定ファイルでは共通の抽象レベルのみを扱い、各アダプターが実際の API パラメータへ変換する。

参照: `../feature-spec.md` §4.1(設定機能)、§5.1(アダプターパターン)、`002-settings-and-llm-adapter.md`。issue #12。

## 対象範囲

### 思考量レベル(抽象)

- `ThinkingLevel`: `off` / `low` / `medium` / `high` の4段階。
- `off` はいずれのプロバイダーでも「思考量パラメータを一切送信しない」ことを意味する(プロバイダー既定の挙動に委ねる)。
- `low` / `medium` / `high` は各アダプターが下表のとおり実際の API パラメータへ変換する。

| レベル | OpenAI (`reasoning_effort`) | Anthropic (`thinking.budget_tokens`) | Gemini (`generationConfig.thinkingConfig.thinkingBudget`) |
| --- | --- | --- | --- |
| off | 送信しない | 送信しない(`thinking` フィールド省略) | 送信しない |
| low | `"low"` | 1024 | 1024 |
| medium | `"medium"` | 2048 | 8192 |
| high | `"high"` | 3072 | 24576 |

Anthropic の `budget_tokens` は `max_tokens`(本アプリでは翻訳応答用に固定 4096)未満である必要があるため、いずれのレベルも 4096 未満の値とする。

### モデルごとの対応可否

- `model_catalog.dart` の `kModelCatalog` を `Map<LlmProvider, List<ModelInfo>>` に拡張する。`ModelInfo` はモデル ID と、対応する `ThinkingLevel` の一覧(`off` を含む)を持つ。
- 思考量に対応しないモデルは `supportedThinkingLevels` に `off` のみを含める。
- 対応表はモデル一覧と同様、コード上の定数として保守する(外部 API からの動的取得は本仕様の対象外、issue #12 コメント参照)。
- 「カスタム」モデル選択時、および `kModelCatalog` に存在しないモデル ID が設定ファイルに残っている場合は、対応可否が不明なため全レベルの選択を許可する(壊れた設定・未知のモデルでも起動・保存を妨げない)。

### 設定画面 UI

- `ModelSelector` の直後に `ThinkingLevelSelector` を配置し、思考量をコンボボックスで選択できるようにする。
- 選択中モデルが思考量に対応していない場合、選択肢は `off` のみ選択可能な状態になり(実質無効化)、対応していない旨の注記を表示する。
- プロバイダー切替(`setProvider`)・モデル切替時、選択中の思考量が新しいモデルで対応していなければ `off` へ自動的にリセットする(対応していれば維持する)。
- 保存導線は既存の「明示的な保存ボタン方式」(`002` の「設定の保存タイミング」節)に従い、他の LLM 設定項目と同様にドラフト編集 → 保存ボタンで永続化する。

### 永続化

- `LlmSettings` に `thinkingLevel`(既定値 `ThinkingLevel.off`)を追加し、`toJson`/`fromJson` で往復する。
- 不正・未知の値は `ThinkingLevel.off` へフォールバックする(`002` の他フィールドと同様、例外を投げない)。

### アダプター層

- `LlmAdapterConfig` に `thinkingLevel` を追加し、`OpenAiAdapter` / `AnthropicAdapter` / `GeminiAdapter` がそれぞれ上表のマッピングに従いリクエストボディへ反映する。
- `off` の場合は該当パラメータを一切送信しない(モデルが対応していない場合に不正なパラメータを送ってエラーになることを避けるため)。

## 対象外

- モデル一覧・思考量対応表の外部 API からの動的取得(issue #12 コメントの通りスコープ外。将来別issueで検討)。
- OpenAI の `minimal` など、本アプリの4段階(`off`/`low`/`medium`/`high`)に含まれない中間値のサポート。
- チャンク分割・リトライ・レスポンス解析への影響(`003-translation-engine.md` の範囲外の変更は行わない)。

## 受け入れ条件

1. 設定画面で「思考量」をコンボボックスから選択でき、選択内容はドラフトに反映される(保存ボタンを押すまで永続化されない、`002` 受け入れ条件13に準拠)。
2. 選択中モデルが思考量に対応していない場合、思考量の選択肢は `off` 以外選択できず、対応していない旨の注記が表示される。
3. プロバイダーを切り替えると、新しいプロバイダーの既定モデルが選択中の思考量に対応していない場合は `off` へリセットされる。対応している場合は維持される。
4. モデルを切り替えると、新しいモデルが選択中の思考量に対応していない場合は `off` へリセットされる。対応している場合は維持される。「カスタム」選択時は制限なくすべてのレベルを選択できる。
5. `thinkingLevel` は設定ファイル(JSON)に保存され、アプリ再起動後も復元される。不正・未知の値は `off` にフォールバックする。
6. OpenAI アダプターは `off` 以外を選択したとき `reasoning_effort` をリクエストボディへ含め、`off` のときは含めないことを単体テストで検証する。
7. Anthropic アダプターは `off` 以外を選択したとき `thinking: { type: "enabled", budget_tokens: N }` をリクエストボディへ含め、`off` のときは `thinking` フィールドを含めないことを単体テストで検証する。
8. Gemini アダプターは `off` 以外を選択したとき `generationConfig.thinkingConfig.thinkingBudget` をリクエストボディへ含め、`off` のときは `thinkingConfig` を含めないことを単体テストで検証する。
9. `flutter analyze` / `flutter test` が成功する。

## 移行上の判断

- 思考量の対応表はモデル一覧と同様にアプリ側の定数として保守し、外部 API からの動的取得は行わない(issue #12 コメントで明示的にスコープ外とされたため)。
- Anthropic の `budget_tokens` は本アプリの固定 `max_tokens`(4096)より小さい値のみを使用する(API 制約 `budget_tokens < max_tokens` を満たすため)。
- モデルごとの思考量対応可否・トークン予算量は、各プロバイダーの公開情報を基にした本アプリ独自の目安値であり、実際の API 仕様変更に応じて随時見直す保守対象とする。
