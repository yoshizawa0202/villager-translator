# 010 追加 LLM プロバイダー対応

- 文書番号: 010
- 文書名: 追加 LLM プロバイダー対応
- 更新日: 2026-08-22
- ステータス: 実装済み(静的解析・テスト・Windows Release ビルド検証済み)
- 対象アプリケーション: VillagerTranslator

## 1. 目的

VillagerTranslator で利用できる LLM プロバイダーとモデルを拡張し、モデルごとに異なる思考量・サンプリング・接続先およびリクエスト形式を、安全かつ一貫した方法で扱えるようにする。

また、プロバイダー固有処理の重複を減らし、モデル能力を一元管理することで、設定画面・入力検証・翻訳リクエストおよび接続確認の挙動が食い違わない構成にする。

最終成果物として、Windows x64 環境で展開後すぐに起動できる Release 版 ZIP を提供する。

## 2. 背景

LLM モデルによって、利用可能な思考量や `temperature` の扱いが異なる。固定された展開 UI や一律のリクエスト生成では、未対応パラメーターの送信や、モデルが受け付けない選択肢の表示が発生する。

このため、モデル能力をカタログに定義し、UI・検証・アダプターおよび送信パラメーターを同じ情報から導出する必要がある。

## 3. 対象範囲

本要件の対象は次のとおりとする。

- DeepSeek、Qwen、Kimi のモデル対応
- Gemini 3.7 Flash の追加と Gemini の既定モデル変更
- OpenAI 互換 API を利用するアダプターの共通化
- モデル依存の思考量 UI、既定値、入力検証および送信形式
- モデル依存のサンプリングパラメーター制御
- Qwen API ベース URL の任意上書き
- API キーのプロバイダー別独立保存
- 接続確認処理と成功メッセージの統一
- HTTP エラーおよびタイムアウトの安全な日本語表示
- セッションログへのプロバイダー ID とモデル名の記録
- アダプター設定生成処理の一元化
- 自動テストの追加・更新
- Flutter 静的解析、テストおよび Windows Release ビルド
- Windows x64 向け ZIP 配布物の作成

## 4. 対象外

次の内容は本要件の対象外とする。

- `reasoning_content` など、モデルの内部推論内容の翻訳結果への取り込み
- DeepSeek の標準モデル選択時における「低」「中」の思考量表示
- Gemini 3.6 以前のモデルを一律に `thinkingLevel` 方式へ移行すること
- 要件で指定されていない Qwen モデルの追加
- 要件で指定されていない Kimi モデルの追加
- Qwen の接続確認で、公式仕様が確認できないモデル一覧 API を使用すること
- Windows インストーラー、Microsoft Store または MSIX による配布
- コード署名証明書の取得および SmartScreen 警告の解消

## 5. 対象プロバイダーおよびモデル

### 5.1 モデル一覧

| プロバイダー | 対象モデル | API モデル ID | 思考量 UI | 既定値 | `temperature` |
|---|---|---|---|---|---|
| DeepSeek | DeepSeek V4 Flash | `deepseek-v4-flash` | OFF / 高 / 最大 | OFF | 送信する |
| DeepSeek | DeepSeek V4 Pro | `deepseek-v4-pro` | OFF / 高 / 最大 | OFF | 送信する |
| Qwen | Qwen3.8-Max | `qwen3.8-max` | OFF / ON | OFF | 送信する |
| Gemini | Gemini 3.7 Flash | `gemini-3.7-flash` | 低 / 中 / 高 | 中 | 送信しない |
| Kimi | Kimi K3 | `kimi-k3` | 低 / 高 / 最大 | 最大 | 送信する |

モデルカタログ上の対象は、Qwen では `qwen3.8-max`、Kimi では `kimi-k3` のみに整理する。`qwen-plus`、`kimi-k2.x` など本要件に含まれないモデルは対象一覧から除外する。

Gemini 3.7 Flash は Gemini プロバイダーの既定モデルとする。

DeepSeek V4 Flash / Pro および Qwen3.8-Max の既定思考量は OFF とする。いずれのモデルも思考量 OFF に対応しており、既存アプリの既定(思考量 OFF)と揃えることで、追加コストの発生する設定を利用者の明示的な選択なしに有効化しないため。

### 5.2 API キー

既存プロバイダーを含む全 6 プロバイダー(`openai`、`anthropic`、`gemini`、`deepseek`、`qwen`、`kimi`)について、API キーを互いに上書きしない形で独立保存する。保存キーはプロバイダー ID から導出する。

API キーをログ、例外メッセージ、画面上のエラー詳細または HTTP 応答本文へ出力してはならない。

## 6. 思考量

### 6.1 共通内部表現

`ThinkingLevel` は次の 6 段階を扱うこと。

| 内部値 | UI 表示 |
|---|---|
| `off` | OFF |
| `on` | ON |
| `low` | 低 |
| `medium` | 中 |
| `high` | 高 |
| `max` | 最大 |

### 6.2 モデル能力情報

モデル能力は `model_catalog.dart` の `ModelCapabilities` に一元化する。

`ModelCapabilities` は少なくとも次の情報を持つこと。

- `supportsTemperature`
- `supportsThinkingOff`
- `thinkingLevels`
- `defaultThinkingLevel`

`supportsThinkingOff` は `thinkingLevels` から導出し、選択肢一覧と OFF 対応可否が食い違わないようにする。

設定 UI の選択肢・既定値・入力検証およびアダプターへ渡す思考量は、この能力情報から導出する。各画面やアダプターが同じ条件を個別にハードコードしない。

思考量を実際の API パラメーター(`reasoning_effort`、`enable_thinking`、`thinkingBudget`、`thinkingLevel`)のどれで送るかという通信形式の対応付けは、各アダプターの責務とする。

### 6.3 DeepSeek の補正

通常のモデル選択 UI では、DeepSeek の思考量として「低」「中」を表示しない。

カスタムモデルなどを経由して `low` または `medium` がアダプターへ渡された場合は、次のように安全な値へ補正する。

| 入力 | 送信値 |
|---|---|
| `low` | `low` |
| `medium` | `high` |

この補正は、API 側で高相当へ丸められる挙動との互換性を確保するための防御処理とする。

## 7. アダプター設計

### 7.1 OpenAI 互換アダプターの共通化

`openai_compatible_adapter_base.dart` を追加し、次のアダプターが継承する。

- OpenAI
- DeepSeek
- Qwen
- Kimi

各アダプター固有の責務は、原則として次の範囲に限定する。

- ベース URL
- 思考量のマッピング
- サンプリングパラメーター
- 疎通確認方法

共通の HTTP 呼び出し、レスポンス解釈および基本的なエラー処理は、可能な限り基底クラスへ集約する。

### 7.2 翻訳結果

OpenAI 互換 API の翻訳結果には、次の値だけを使用する。

```text
choices[0].message.content
```

`reasoning_content` は翻訳結果へ連結せず、画面表示や保存対象にも含めない。

### 7.3 アダプター設定生成

アダプター生成に必要な設定は、`LlmSettings.toAdapterConfig()` の 1 か所で構築する。

4 つの翻訳オーケストレーターは個別に設定を組み立てず、`toAdapterConfig()` の結果を使用する。

Qwen 用ベース URL の上書き値は Qwen アダプターだけへ渡し、他プロバイダーへ渡さない。

## 8. Gemini 3.7 Flash

Gemini 3.7 Flash では、思考量として次を送信する。

```text
thinkingConfig.thinkingLevel
```

Gemini 3.7 Flash には次のパラメーターを送信しない。

- `thinkingBudget`
- `temperature`
- `topP`
- `topK`
- `candidateCount`

Gemini 3.6 以前を含む既存 Gemini モデルは、既存仕様に従い `thinkingBudget` と `temperature` を使用する。既存モデルの挙動を本対応によって変更しない。

## 9. Qwen API ベース URL

`LlmSettings` に `qwenBaseUrl` を追加する。

詳細設定画面には「Qwen API ベース URL(任意)」入力欄を追加し、Qwen が選択されている場合だけ表示する。

入力値の扱いは次のとおりとする。

- 空欄の場合は国際向けエンドポイント(`https://dashscope-intl.aliyuncs.com/compatible-mode/v1`)を使用する
- 入力されている場合は URL 形式を検証する
- URL として不正な場合は送信前に日本語の検証エラーを表示する
- Qwen 以外を選択している場合、その設定値を対象アダプターへ渡さない

## 10. 接続確認

接続確認が成功した場合のメッセージは、全対象プロバイダーで次に統一する。

```text
API接続に成功しました。
```

Qwen の接続確認は、互換モードのモデル一覧取得 API を公式資料で確認できないため、Chat Completion へ最小リクエストを 1 回送る方式とする。

Qwen の最小接続確認では、生成量を 1 トークン相当に制限し、不要な複数リクエストを送らない。

## 11. エラーおよびタイムアウト

`http_llm_adapter_base.dart` で、少なくとも次の状態を利用者向けの日本語メッセージへ変換する。

- HTTP 401
- HTTP 403
- HTTP 404
- HTTP 429
- HTTP 5xx
- 通信タイムアウト

HTTP 通信のタイムアウトは 3 分とする。

利用者向けエラーメッセージには次を含めない。

- API キー
- Authorization ヘッダー
- HTTP 応答本文
- プロバイダーから返された機密情報または内部情報

## 12. ログ

セッションログの開始行に次を記録する。

- プロバイダー ID
- モデル名

API キー、Authorization ヘッダーおよび秘密情報は記録しない。

## 13. 受け入れ条件

### AC-01: 対象モデル

モデルカタログに DeepSeek V4 Flash、DeepSeek V4 Pro、Qwen3.8-Max、Gemini 3.7 Flash および Kimi K3 が定義されていること。

### AC-02: 不要モデルの除外

Qwen の対象を `qwen3.8-max`、Kimi の対象を `kimi-k3` に整理し、`qwen-plus`、`kimi-k2.x` など要件外の追加モデルが通常のモデル一覧に表示されないこと。

### AC-03: API キーの独立保存

既存プロバイダーを含む全 6 プロバイダーの API キーが独立して保存され、あるプロバイダーの API キー更新が別プロバイダーの保存値へ影響しないこと。

### AC-04: 思考量の内部表現

`ThinkingLevel` が `off`、`on`、`low`、`medium`、`high`、`max` の 6 段階を扱うこと。

### AC-05: モデル能力の一元管理

`ModelCapabilities` に温度対応、思考 OFF 対応、利用可能な思考量および既定思考量が定義されていること。

### AC-06: モデル依存 UI

モデルを切り替えると思考量 UI がモデルカタログの能力情報に従って切り替わり、対象モデルで利用できない選択肢が表示されないこと。

### AC-07: モデル依存の検証と送信

思考量の入力検証、既定値および送信パラメーターが、UI と同じモデル能力情報から導出されること。

### AC-08: DeepSeek の挙動

DeepSeek V4 Flash および Pro では思考量 UI が OFF、高、最大となり、`temperature` を送信すること。カスタムモデル経由で `medium` が渡された場合は `high` へ補正されること。

### AC-09: Qwen の挙動

Qwen3.8-Max では思考量 UI が OFF、ON となり、`temperature` を送信すること。

### AC-10: Gemini 3.7 Flash の挙動

Gemini 3.7 Flash では思考量 UI が低、中、高、既定値が中となること。`thinkingConfig.thinkingLevel` を送信し、`thinkingBudget`、`temperature`、`topP`、`topK` および `candidateCount` を送信しないこと。

### AC-11: 既存 Gemini の互換性

Gemini 3.7 Flash 以外の既存 Gemini モデルでは、従来どおり `thinkingBudget` と `temperature` を使用し、既存動作が維持されること。

### AC-12: Kimi の挙動

Kimi K3 では思考量 UI が低、高、最大、既定値が最大となり、`temperature` を送信すること。

### AC-13: OpenAI 互換アダプター

OpenAI、DeepSeek、Qwen および Kimi のアダプターが共通基底クラスを使用し、各アダプターの固有処理がベース URL、思考量、サンプリングおよび疎通確認を中心とした最小限の差分になっていること。

### AC-14: 翻訳結果の抽出

OpenAI 互換 API の翻訳結果として `choices[0].message.content` だけを使用し、`reasoning_content` が取り込まれないことをテストで確認できること。

### AC-15: Qwen ベース URL

Qwen 選択時だけ任意のベース URL 入力欄が表示され、空欄では国際向けエンドポイント、不正な URL では検証エラーとなること。上書き値を Qwen 以外のアダプターへ渡さないこと。

### AC-16: 接続確認

接続確認成功時に「API接続に成功しました。」と表示されること。Qwen では最小 Chat Completion を 1 回だけ送信して確認すること。

### AC-17: エラーとタイムアウト

401、403、404、429、5xx および 3 分のタイムアウトが安全な日本語メッセージへ変換され、応答本文や API キーがメッセージへ含まれないこと。

### AC-18: 設定・ログ・品質検証

アダプター設定生成が `LlmSettings.toAdapterConfig()` に集約され、セッションログ開始行にプロバイダー ID とモデル名が記録されること。能力情報、4 アダプターのマッピング、Qwen ベース URL、6 プロバイダーの API キー独立保存、モデル依存 UI を含む自動テストがあり、`flutter analyze` と `flutter test` が成功すること。

### AC-19: Windows Release 配布物

`flutter build windows --release` が成功し、Windows x64 用 `VillagerTranslator-windows-x64.zip` が生成されること。利用者が ZIP を展開し、同梱された `VillagerTranslator.exe` をダブルクリックするだけで起動できること。実行に必要な `data` ディレクトリ、Flutter DLL、プラグイン DLL および必要な Visual C++ ランタイムが欠落なく同梱されること。

## 14. 設計上の判断

### 14.1 モデルカタログを唯一の判断元とする

モデルごとの条件分岐を UI、検証およびアダプターへ分散させると、将来のモデル追加時に不整合が生じやすい。このため `ModelCapabilities` をモデル能力の唯一の判断元とする。

### 14.2 OpenAI 互換処理を共通化する

OpenAI、DeepSeek、Qwen および Kimi は互換性の高い API 形式を利用するため、基底アダプターへ共通処理を集約し、プロバイダー差分だけを派生クラスへ残し、修正漏れとテスト重複を減らす。

### 14.3 Gemini 3.7 Flash を明示的に分岐する

Gemini 3.7 Flash はサンプリングおよび思考量の仕様が既存 Gemini モデルと異なるため、このモデルだけ `thinkingLevel` 方式を使用する。既存モデルは後方互換性を優先して変更しない。分岐対象は `GeminiAdapter.thinkingLevelModels` に定義する。

### 14.4 推論内容を翻訳結果へ含めない

内部推論は利用者が要求した翻訳本文ではなく、機密情報や不要な説明を含む可能性がある。このため `message.content` のみを結果として採用する。

### 14.5 Qwen の接続確認には最小生成を使用する

公式に確認できないモデル一覧 API へ依存せず、実際の翻訳経路に近い Chat Completion を最小生成量で 1 回だけ呼び出す。これにより、API キー、ベース URL およびモデル利用可否を同時に確認する。

### 14.6 エラー処理を HTTP 基底クラスへ集約する

認証失敗、レート制限、サーバー障害およびタイムアウトの表示を統一し、個別アダプターが応答本文や秘密情報を誤って表示するリスクを無くす。

### 14.7 ZIP 配布では実行ファイルだけを配布しない

Flutter Windows アプリは EXE 単体では動作しない。`data`、Flutter DLL、プラグイン DLL および必要な Visual C++ ランタイムを同じ配布物へ含める。

## 15. テスト方針

少なくとも次を自動テストで確認する。

- 各モデルの `ModelCapabilities`
- モデル変更時の思考量 UI
- モデルごとの既定思考量
- モデルごとの `temperature` 送信有無
- Gemini 3.7 Flash の送信パラメーターと禁止パラメーター
- 既存 Gemini モデルの後方互換性
- DeepSeek、Qwen および Kimi の思考量マッピング
- `choices[0].message.content` の抽出
- `reasoning_content` が結果へ混入しないこと
- Qwen ベース URL の空欄、不正 URL、正常 URL
- Qwen ベース URL を他プロバイダーへ渡さないこと
- 全 6 プロバイダーの API キー独立保存
- 401、403、404、429、5xx およびタイムアウトのメッセージ
- エラーへ API キー、応答本文が含まれないこと
- 接続確認成功メッセージ
- セッションログ開始行のプロバイダー ID とモデル名

3 分のタイムアウトは `fake_async` による仮想時間で検証し、テスト実行を実時間で待たせない。

リリース前に次を順番に実行し、すべて成功させること。

```powershell
flutter pub get
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test
flutter build windows --release
```

## 16. 配布物

配布ファイル名は次とする。

```text
VillagerTranslator-windows-x64.zip
```

ZIP 直下には、少なくとも次を含める。

```text
VillagerTranslator.exe
flutter_windows.dll
data/
各プラグインが必要とする DLL
msvcp140.dll
vcruntime140.dll
vcruntime140_1.dll
```

リリース候補は、ビルド環境とは別の Windows 環境または新しい展開先へ ZIP を展開し、EXE の起動、設定画面、プロバイダー選択、API 接続確認および短い翻訳を確認する。

## 17. 今後の検討事項

- Google の現行仕様では `thinkingBudget` は後方互換用として維持され、`thinking_level` 方式への移行が推奨されている。Gemini 3.6 以前を含む全 Gemini モデルの移行は別要件として検討する。
- Windows 配布時の SmartScreen 警告を回避する場合は、コード署名と証明書管理を別要件として検討する。
- インストーラー形式が必要になった場合は、MSIX などの採用を別要件として検討する。
- DeepSeek V4 Flash / Pro の API モデル ID、および Qwen 国際向けエンドポイントの URL は、各プロバイダーの公式資料で確定できていない。実際の API キーで接続確認を行い、相違があればモデルカタログとアダプターの既定値を更新する。本書の基本方針、送信禁止事項、安全要件および配布要件はその場合も維持する。
