# 012: Minecraft インスタンス一括翻訳

- 文書番号: 012
- 文書名: Minecraft インスタンス一括翻訳
- 更新日: 2026-08-24
- ステータス: 実装済み(静的解析・テスト・Windows Release ビルド検証済み)
- 対象アプリケーション: VillagerTranslator

## 目的

`011-launcher-instance-discovery.md` で検出・解析した Minecraft インスタンスに対し、MOD・クエスト・ガイドブックをまとめて翻訳する機能を追加する。

利用者は次の操作だけで翻訳を完了できるようにする。

```text
翻訳対象を選択
↓
対象言語を選択
↓
LLMモデルを選択
↓
翻訳モードを選択
↓
「すべて翻訳」
```

大量の API リクエストが発生し得るため、実行前に対象件数と文字列数を確認できるようにする。また、1 件の失敗で全体を止めず、失敗項目だけを再試行できるようにする。

参照: `../feature-spec.md` §4.2(翻訳設定)、§5.5(差分更新ロジック)、§6.2(MOD 翻訳・リソースパック生成)、§10(進捗表示・キャンセル)、§11(ログ機能)、§12(バックアップ機能)、§13(翻訳履歴機能)、`004-mod-translation.md`、`005-quest-translation.md`、`006-patchouli-translation.md`、`008-progress-log-history.md`、`011-launcher-instance-discovery.md`。issue #18。

## 対象範囲

### 1. 一括翻訳の位置づけ

インスタンス一括翻訳は、既存の翻訳処理を駆動する上位機能として追加する。新しい翻訳ロジック(チャンク分割、応答検証、リトライ、出力生成、バックアップ)は一切追加しない。

```text
InstanceTranslationPlan
        │
        ▼
InstanceTranslationOrchestrator
        │
        ├─ ModTranslationOrchestrator.translateAndPack()
        ├─ QuestTranslationOrchestrator.translateAndWrite()
        └─ PatchouliTranslationOrchestrator.translateAndWrite()
```

### 2. InstanceTranslationPlan

インスタンス一括翻訳 1 回分を表すモデルを追加する。

`lib/domain/instancetranslation/instance_translation_plan.dart`

```dart
class InstanceTranslationPlan {
  final MinecraftInstance instance;

  final String targetLanguageId;
  final String targetLanguageDisplayName;

  final bool translateMods;
  final bool translateQuests;
  final bool translateGuidebooks;

  final List<ModScanEntry> mods;
  final List<QuestScanEntry> quests;
  final List<PatchouliBookEntry> guidebooks;

  final InstanceTranslationMode mode;

  final LlmProvider provider;
  final String model;
}
```

対象一覧には、既存のスキャン結果の型(`ModScanEntry`、`QuestScanEntry`、`PatchouliBookEntry`)をそのまま持たせる。既存オーケストレーターの `selectedEntries` へ無変換で渡すためであり、これらを包む新しい対象モデルは追加しない。

これにより次が成立する。

```text
1 Minecraftインスタンス = 1 翻訳ジョブ
```

### 3. 翻訳対象の選択

カテゴリごとに個別に ON / OFF できるようにする。

```text
Prominence II

翻訳対象

☑ MOD
  194個

☑ クエスト
  FTB Quests

☑ ガイドブック
  23冊

対象言語
日本語

モデル
Gemini 3.7 Flash

[すべて翻訳]
```

- 各カテゴリのチェックボックスは、`011` の自動解析で 1 件以上検出されたカテゴリのみ操作可能とする。0 件のカテゴリは「未検出」と表示し、無効化する。
- カテゴリ内の個別項目(MOD 1 件単位など)の選択は行わない。個別選択が必要な場合は既存の 4 タブ画面を使う。
- 全カテゴリが OFF の場合、`[すべて翻訳]` を無効化する。

### 4. 対象言語・LLM モデル・翻訳モードの指定

対象言語、LLM プロバイダー、モデル、翻訳モードを 1 画面で指定する。

- 対象言語は `TranslationSettings.allLanguages`(既定 9 言語 + カスタム言語)から選ぶ。既定値は既定言語の先頭とする。
- プロバイダーとモデルの選択肢および表示は、既存のモデルカタログ(`lib/domain/llm/model_catalog.dart`)から導出する。設定画面の `ProviderSelector` / `ModelSelector` と同じ情報源を使い、この画面が独自にモデル一覧を持たない。
- 既定値は保存済み設定(`AppSettings.llm`)の値とする。
- API キーは既存の `SettingsController.apiKeyFor(provider)` から取得する。選択したプロバイダーの API キーが未設定の場合は、日本語のエラーメッセージを表示して実行させない。
- 思考量(`ThinkingLevel`)、`temperature`、チャンクサイズなどの詳細設定は本画面に出さず、保存済み設定の値をそのまま使う。

この画面での選択は**その実行だけの上書き**とし、保存済み設定(`settings.json`)を書き換えない。実行時に `AppSettings.copyWith()` で上書きした設定を各オーケストレーターへ渡す。

### 5. 翻訳モード

既存翻訳の扱いを 3 つから選べるようにする。内部表現は既存の `ExistingTranslationPolicy`(`lib/domain/settings/existing_translation_policy.dart`)へ写像し、新しい列挙を追加しない。

| 画面表示 | `ExistingTranslationPolicy` | 意味 |
|---|---|---|
| 未翻訳のみ | `skip` | 対象言語ファイルが既に存在する対象は翻訳しない |
| 差分更新 | `diffUpdate` | 不足しているキーのみを翻訳して追記する(既定) |
| すべて再翻訳 | `retranslateAll` | 既存の有無に関わらず全キーを翻訳し直す |

`011` の自動解析結果から、翻訳済み・未翻訳の内訳を表示する。

```text
翻訳可能MOD  194
翻訳済み      73
未翻訳       121
```

内訳は各スキャン結果が持つ `hasExistingTranslation` から集計する(`011` 第 16 節)。

### 6. 翻訳前サマリー

`[すべて翻訳]` の押下後、実行前に対象を確認するダイアログを必ず表示する。

```text
翻訳対象を確認してください

Prominence II

MOD
194個
36,421文字列

FTB Quests
912文字列

Patchouli
23冊
3,184文字列

────────────────

合計
40,517文字列

モデル
Gemini 3.7 Flash

対象言語
日本語

[戻る]  [翻訳開始]
```

集計は純粋関数 `lib/domain/instancetranslation/instance_translation_estimate.dart` に置く。`ModScanEntry.sourceEntries`、`QuestScanEntry.sourceEntries`、`PatchouliBookEntry.sourceEntries` はいずれも `Map<String, String>` であるため、次を数えるだけで足りる。

- カテゴリごとの対象件数
- カテゴリごとの翻訳対象文字列数(`sourceEntries` のエントリ数)
- 全カテゴリの合計文字列数

翻訳モードが「未翻訳のみ」の場合、既に翻訳済みの対象を件数・文字列数から除外して表示する。「差分更新」の場合、既存キーの実チェックは翻訳直前にオーケストレーター内部で行われるため、サマリーでは全キーを上限値として表示し、その旨を注記する。

### 7. 一括翻訳の処理順

次の順に処理する。

```text
1. MOD言語ファイル
↓
2. クエスト
↓
3. ガイドブック
↓
4. 出力検証
↓
5. 完了
```

各カテゴリの処理は、既存オーケストレーターをそのまま呼び出す。

| カテゴリ | 呼び出す処理 |
|---|---|
| MOD | `ModTranslationOrchestrator.translateAndPack()` |
| クエスト | `QuestTranslationOrchestrator.translateAndWrite()` |
| ガイドブック | `PatchouliTranslationOrchestrator.translateAndWrite()` |

3 つはいずれも `profileDirectory` / `selectedEntries` / `targetLanguageId` / `targetLanguageDisplayName` / `settings` / `apiKey` / `sessionId` / `cancellationToken` と 4 種の進捗コールバックという同形のシグネチャを持つため、共通の駆動ループに載せる。`profileDirectory` には `MinecraftInstance.rootPath` を渡す。

「出力検証」では、各カテゴリの結果から出力先の存在を確認する。

- MOD: `ModTranslateAndPackResult.packDirectory`(全対象スキップ時は `null`、これは失敗ではない)
- クエスト: `QuestTranslateAndWriteResult.writtenFiles`
- ガイドブック: `PatchouliTranslateAndWriteResult.updatedJarRelativePaths`

### 8. セッションとログ・バックアップ

1 回の一括翻訳を 1 セッションとして扱い、3 カテゴリで同じ `sessionId` を共有する。

出力先は既存の規約(`lib/infrastructure/common/session_paths.dart`)に従う。

```text
{rootPath}/logs/localizer/{sessionId}/
├─ session.log
├─ translation_summary.json
└─ backup/
   ├─ resource_pack/
   ├─ snbt_original/
   └─ patchouli_jar/
```

バックアップのサブディレクトリ名はカテゴリごとに異なるため、`sessionId` を共有しても衝突しない。

`translation_summary.json` は各オーケストレーターが自身の結果で上書きする。このため、3 カテゴリすべての処理が終わった後に、上位オーケストレーターが 3 つの `TranslationSummary.items` を連結した統合サマリーを同じ `sessionId` で 1 回書き直す(`TranslationSummaryWriter.write()`)。既存オーケストレーターおよび `TranslationSummaryWriter` には変更を加えない。

セッションログには、既存の `SessionLogger` を用いて次を記録する。

- セッション開始行(プロバイダー ID とモデル名を含む。`010-additional-llm-providers.md` §12)
- カテゴリの開始・終了
- 対象 1 件ごとの成功・失敗
- チャンク単位の結果(既存の `onChunkResult` 経由)
- 完了時のサマリー

API キー、Authorization ヘッダー、HTTP 応答本文は記録しない。

### 9. 進捗表示

一括翻訳中は、カテゴリ別と全体の進捗を表示する。

```text
Prominence II を翻訳しています

MOD
194 / 194
100%

クエスト
142 / 198
72%

ガイドブック
0 / 23
0%

────────────────

全体
61%
```

- 現在処理している MOD 名・クエストファイル名・ガイドブック名を表示する(既存の `CurrentItemCallback` 経由)。
- 進捗モデルは既存の `OverallProgress` / `ChunkProgress`(`lib/domain/common/translation_progress.dart`)をそのまま使う。カテゴリ別進捗は各オーケストレーターの `onOverallProgress` をカテゴリごとに保持し、全体進捗は全カテゴリの完了件数の合算として算出する。
- 表示ウィジェットは既存の `TranslationProgressPanel`(`lib/features/shell/widgets/translation_progress_panel.dart`)を再利用し、カテゴリ行を積むラッパーのみ新設する。
- キャンセルは既存の `CancellationToken` を 3 オーケストレーターへ共有して渡す。確認ダイアログは既存の `CancelConfirmationDialog` を使う。
- キャンセルすると、実行中のカテゴリが協調的に停止し、後続カテゴリは開始しない。それまでの成果物とログは保持する。

### 10. 部分失敗への対応

1 つの MOD・クエスト・ガイドブックで翻訳に失敗しても、一括処理全体を停止しない。

- カテゴリ単位で例外を捕捉し、そのカテゴリが失敗しても後続カテゴリの処理を継続する。
- カテゴリ内の対象 1 件の失敗は、既存オーケストレーターの結果(翻訳された対象識別子 / スキップされた対象識別子 / 出力の有無)から判定する。MODの対象識別子にはMOD IDではなくJAR相対パスを使う。
- 結果は `lib/domain/instancetranslation/instance_translation_outcome.dart` に集約する。

```text
翻訳完了

成功
216件

失敗
2件

スキップ
17件

[失敗した項目を再試行]
```

- 「成功」は翻訳が完了し出力へ反映された対象、「失敗」は例外またはリトライ上限超過により反映されなかった対象、「スキップ」は翻訳モードにより対象外となった対象とする。
- `[失敗した項目を再試行]` は、失敗した対象だけを `mods` / `quests` / `guidebooks` に絞った新しい `InstanceTranslationPlan` を組み直し、同じ実行経路を再実行する。再試行専用の経路は作らない。
- MODの再試行対象はJAR相対パスで照合する。同じMOD IDの別JARを誤って再試行対象へ含めない。
- 再試行は新しい `sessionId` で実行し、元のセッションのログ・バックアップを上書きしない。
- LLM 応答のチャンク単位リトライは既存の `lib/domain/translation/retry_policy.dart` が担当する。本仕様の再試行はその上位にある「対象 1 件単位の再実行」であり、別レイヤであることをコメントおよびログ表記で区別する。

### 11. Resource Pack 仕様(pack_format)の自動設定

Minecraft バージョンを取得できる場合、生成するリソースパックの `pack_format` を自動調整する。

```text
Minecraft Version
↓
対応Resource Pack仕様を判定
↓
pack.mcmeta生成
```

`lib/domain/instancetranslation/resource_pack_format.dart` に、Minecraft バージョン文字列から `pack_format` を求める純粋関数を追加する。

| Minecraft バージョン | `pack_format` |
|---|---|
| 1.6.1 〜 1.8.9 | 1 |
| 1.9 〜 1.10.2 | 2 |
| 1.11 〜 1.12.2 | 3 |
| 1.13 〜 1.14.4 | 4 |
| 1.15 〜 1.16.1 | 5 |
| 1.16.2 〜 1.16.5 | 6 |
| 1.17 〜 1.17.1 | 7 |
| 1.18 〜 1.18.2 | 8 |
| 1.19 〜 1.19.2 | 9 |
| 1.19.3 | 12 |
| 1.19.4 | 13 |
| 1.20 〜 1.20.1 | 15 |
| 1.20.2 | 18 |
| 1.20.3 〜 1.20.4 | 22 |
| 1.20.5 〜 1.20.6 | 32 |
| 1.21 〜 1.21.1 | 34 |

この対応表の各境界値は「要検証項目」に含める。

フォールバック規則は次のとおりとする。

- Minecraft バージョンが取得できない(`Unknown`)場合、現行の既定値 `9` を使用する
- 対応表の最も古いバージョンより前の場合、現行の既定値 `9` を使用する
- 対応表の最も新しいバージョンより後の場合、対応表の最大エントリの値を使用し、推定値である旨を画面に表示する

既存の `lib/domain/modtranslation/resource_pack_builder.dart` の `buildPackMcmeta()` および `buildResourcePackFiles()` には、`pack_format` を受け取る**任意引数**を追加する。省略時は現行どおり `kResourcePackFormat`(= 9)を使用する。

これにより、インスタンスを経由しない既存の MOD タブからの呼び出しと既存テスト(`test/domain/modtranslation/resource_pack_builder_test.dart`)は変更なしで従来どおり動作する。

一括翻訳から `ModTranslationOrchestrator.translateAndPack()` を呼ぶ経路でのみ、判定した `pack_format` を渡す。

### 12. 完了通知

一括翻訳の完了時、既存の `SystemNotifier`(`lib/infrastructure/common/system_notifier.dart`)でシステム通知を出す。通知本文には成功・失敗・スキップの件数を含める。

完了画面には次を表示する。

- カテゴリごとの成功・失敗・スキップ件数
- 出力先(リソースパックのディレクトリ、書き込んだクエストファイル、更新した JAR)
- バックアップの保存先
- セッションログを開く導線(既存の `LogViewerDialog`)

### 13. 既存機能との互換性

次の既存機能は削除しない。

- MOD 個別翻訳
- クエスト個別翻訳
- Patchouli 個別翻訳
- カスタムファイル翻訳
- プロファイルフォルダの手動指定
- 差分更新
- バックアップ
- 翻訳履歴

インスタンス一括翻訳は、既存機能を利用した上位機能として追加する。

## 対象外

次の内容は本仕様の対象外とする。

- カスタムファイル翻訳の一括翻訳への組み込み(対象ディレクトリが利用者指定であり、インスタンス構造から自動決定できないため)
- カテゴリ内の個別項目(MOD 1 件単位など)の選択 UI
- 複数インスタンスの同時一括翻訳
- カテゴリの並列実行(処理順は MOD → クエスト → ガイドブックの直列に固定する)
- 一括翻訳画面での思考量・`temperature`・チャンクサイズの上書き
- 翻訳コスト(料金)の見積り表示
- `pack.mcmeta` の `supported_formats` による対応範囲の拡張
- お気に入り登録機能(`011` と同じく別要件として検討する)

## 設計判断

### 新しい翻訳ロジックを書かない

MOD・クエスト・Patchouli の 3 オーケストレーターは、`004`〜`006` と `008` を通じて既にチャンク分割・リトライ・進捗通知・キャンセル・バックアップ・サマリ出力を備えており、シグネチャも同形である。

一括翻訳のためにこれらを再実装すると、差分更新の判定や SNBT の原本保全といった既に検証済みのロジックが二重化し、片方だけ修正される不整合を生む。このため上位オーケストレーターは「3 つを順に呼び、結果を集約する」ことだけを責務とする。

### 翻訳モードを既存の ExistingTranslationPolicy へ写像する

issue #18 の「未翻訳のみ / 差分更新 / すべて再翻訳」は、既存の `ExistingTranslationPolicy` の 3 値と 1 対 1 で対応する。新しい列挙を追加すると、同じ概念を表す型が 2 つ存在することになり、オーケストレーターへ渡す直前で必ず変換が必要になる。

このため列挙は増やさず、画面表記だけ issue の用語に合わせる。

### 実行時の指定を保存済み設定へ書き戻さない

一括翻訳画面で選ぶモデル・言語・翻訳モードは「この実行をどうするか」であり、アプリの既定設定とは別の概念である。ここでの選択を `settings.json` へ書き戻すと、設定画面で意図して選んだ値が翻訳のたびに上書きされる。

このため `AppSettings.copyWith()` による実行時上書きにとどめる。`SettingsController.save()` は呼ばない。

### 統合サマリーを最後に 1 回書き直す

3 オーケストレーターはそれぞれ `translation_summary.json` を書く。同じ `sessionId` を共有すると、後続カテゴリの書き込みが先行カテゴリの内容を上書きする。

これを避ける方法は 2 つある。

1. カテゴリごとに別 `sessionId` を使う
2. 3 カテゴリ完了後に統合サマリーを同じ `sessionId` で書き直す

1 は既存コードを変更せずに済むが、1 回の一括翻訳が翻訳履歴に 3 件のセッションとして並び、ログとバックアップも 3 か所へ分散する。issue #18 の「1 Minecraft インスタンス = 1 翻訳ジョブ」という位置づけと合わない。

このため 2 を採用する。既存オーケストレーターと `TranslationSummaryWriter` はいずれも無変更のまま利用でき、最後の書き込みが統合結果で上書きする。

処理途中でキャンセル・異常終了した場合、`translation_summary.json` には最後に完了したカテゴリの内容が残る。これは形式として不正ではなく、既存の履歴画面(`HistoryRepository`)がそのまま読める。統合サマリーの書き込みは、キャンセル時も含めて処理終了時に必ず 1 回行う。

### 対象モデルに既存のスキャン結果型をそのまま持たせる

issue #18 の概念例は `ModTranslationTarget` などの独自型を挙げているが、既存オーケストレーターの `selectedEntries` は `List<ModScanEntry>` / `List<QuestScanEntry>` / `List<PatchouliBookEntry>` を要求する。

独自型を挟むと、`sourceEntries` や `snbtOriginalContent` といった翻訳に必須のデータを保持したまま相互変換する層が必要になり、変換漏れが翻訳結果の欠落として現れる。このため `InstanceTranslationPlan` は既存の型をそのまま保持する。

### 対象 1 件単位の再試行とチャンク単位のリトライを分ける

既存の `retry_policy.dart` は、LLM 応答の失敗に対するチャンク単位の自動リトライである。本仕様の「失敗した項目を再試行」は、リトライを使い切って失敗した対象を、利用者の明示的な操作で改めて処理し直すものである。

両者を同一視すると、自動リトライ回数の設定変更が利用者操作の挙動を変えてしまう。このため別レイヤとして扱い、ログ上も区別できる表記にする。

### pack_format の自動判定を任意引数で入れる

`kResourcePackFormat = 9` を書き換えると、既存の MOD タブ経由の出力とその受け入れ条件(`004-mod-translation.md`)にも影響が及ぶ。インスタンス経由でのみ Minecraft バージョンが分かるため、判定できる経路だけが新しい値を使い、判定できない経路は従来の値を維持する形が安全である。

このため `buildPackMcmeta()` / `buildResourcePackFiles()` へ任意引数として追加し、既定値は現行の定数のままとする。

### カスタムファイル翻訳を一括対象に含めない

カスタムファイル翻訳は、利用者が任意のディレクトリを指定する汎用のフォールバック経路であり(`007-custom-files-translation.md`)、インスタンスの構造から対象を自動決定できない。既存翻訳のスキップ・差分更新の概念も持たないため、翻訳モードの適用対象にもならない。

このため一括翻訳の対象カテゴリには含めず、既存タブでの利用を維持する。

## 受け入れ条件

### AC-01: 翻訳計画モデル

`InstanceTranslationPlan` が対象インスタンス、対象言語、カテゴリ別の ON / OFF、カテゴリ別の対象一覧、翻訳モード、プロバイダーおよびモデルを保持すること。対象一覧が既存の `ModScanEntry` / `QuestScanEntry` / `PatchouliBookEntry` を無変換で保持すること。

### AC-02: カテゴリ別の ON / OFF

MOD のみ、クエストのみ、ガイドブックのみ、すべて、のいずれの組み合わせでも翻訳を実行できること。0 件のカテゴリが選択不可になり、全カテゴリが OFF のとき実行できないこと。

### AC-03: 翻訳モード

「未翻訳のみ」「差分更新」「すべて再翻訳」がそれぞれ `ExistingTranslationPolicy.skip` / `diffUpdate` / `retranslateAll` として各オーケストレーターへ渡ること。

### AC-04: 実行時設定の非永続化

一括翻訳画面で選んだ言語・プロバイダー・モデル・翻訳モードが `settings.json` へ書き戻されないこと。実行時は `AppSettings.copyWith()` による上書き値が使われること。

### AC-05: モデル選択の情報源

プロバイダーおよびモデルの選択肢が既存のモデルカタログから導出され、この画面が独自のモデル一覧を持たないこと。選択したプロバイダーの API キーが未設定の場合に、日本語のエラーメッセージが表示され実行されないこと。

### AC-06: 翻訳前サマリー

実行前に確認ダイアログが必ず表示され、カテゴリごとの件数・文字列数、合計文字列数、モデル、対象言語が表示されること。「戻る」で実行されないこと。翻訳モードが「未翻訳のみ」のとき、翻訳済み対象が件数・文字列数から除外されること。

### AC-07: 処理順

MOD → クエスト → ガイドブック → 出力検証 → 完了の順に処理されること。

### AC-08: セッションの一体性

3 カテゴリが同一の `sessionId` を共有し、ログ・バックアップ・サマリーが `{rootPath}/logs/localizer/{sessionId}/` 配下へ集約されること。カテゴリごとのバックアップサブディレクトリが衝突しないこと。

### AC-09: 統合サマリー

処理終了時に、3 カテゴリの結果を連結した統合 `translation_summary.json` が同じ `sessionId` で書き出されること。キャンセル時および一部カテゴリの失敗時にも書き出されること。既存の `HistoryRepository` がそれを読めること。

サマリーの書き出し自体がディスク容量不足・権限エラー等で失敗した場合も、そこまでに完了したカテゴリの結果は呼び出し元へ返すこと。書き出しの失敗を理由に翻訳結果を失わせない(失敗はログにのみ残し、「失敗した項目を再試行」を引き続き使えること)。

### AC-10: 進捗表示

カテゴリ別の進捗と全体進捗が同時に表示され、現在処理中の対象名が表示されること。全体進捗が全カテゴリの完了件数の合算から算出されること。

### AC-11: キャンセル

実行中にキャンセルでき、実行中カテゴリが協調的に停止し、後続カテゴリが開始されないこと。それまでの成果物とログが保持されること。

### AC-12: 部分失敗時の継続

1 つの MOD・クエスト・ガイドブックの失敗で一括処理全体が停止しないこと。1 つのカテゴリが例外で失敗しても後続カテゴリが処理されること。

### AC-13: 失敗項目の記録と再試行

成功・失敗・スキップの件数が完了画面に表示され、失敗した対象が記録されること。`[失敗した項目を再試行]` により失敗対象だけに絞った計画で再実行され、新しい `sessionId` が使われること。MODはJAR相対パスで照合し、同じMOD IDを持つ別JARを誤選択しないこと。

### AC-14: pack_format の自動判定

Minecraft バージョンを取得できる場合、対応表に従った `pack_format` で `pack.mcmeta` が生成されること。取得できない場合と対応表より古いバージョンの場合に `9` へフォールバックすること。対応表より新しい場合に最大エントリの値が使われ、推定値である旨が表示されること。

### AC-15: 既存出力経路の非破壊

`buildPackMcmeta()` / `buildResourcePackFiles()` の `pack_format` 引数が任意であり、省略時に従来どおり `9` が使われること。既存テスト `test/domain/modtranslation/resource_pack_builder_test.dart` が変更なしで成功すること。

### AC-16: 完了通知

完了時にシステム通知が表示され、成功・失敗・スキップの件数が含まれること。完了画面に出力先・バックアップ先・ログを開く導線が表示されること。

### AC-17: ログの安全性

セッションログ開始行にプロバイダー ID とモデル名が記録され、API キー・Authorization ヘッダー・HTTP 応答本文が記録されないこと。

### AC-18: 既存機能の維持

MOD / クエスト / Patchouli の個別翻訳、カスタムファイル翻訳、プロファイルフォルダの手動指定、差分更新、バックアップ、翻訳履歴が従来どおり利用できること。

### AC-19: 品質検証

`flutter analyze` と `flutter test` が成功すること。計画モデル、集計、処理順、部分失敗、再試行、pack_format 判定を対象とする自動テストがあること。

## テスト方針

少なくとも次を自動テストで確認する。

**集計・判定(domain、純粋関数)**

- カテゴリごとの件数・文字列数、および合計の集計
- 翻訳モード「未翻訳のみ」のときに翻訳済み対象が集計から除外されること
- 翻訳モードから `ExistingTranslationPolicy` への写像
- Minecraft バージョンから `pack_format` を求める各境界値
- バージョン不明・対応表より古い場合に `9` を返すこと
- 対応表より新しい場合に最大エントリの値を返すこと
- 不正なバージョン文字列(空文字、`Unknown`、`1.x`、接尾辞つき)で例外を投げないこと

**上位オーケストレーター(infrastructure)**

- モック化した 3 オーケストレーターが MOD → クエスト → ガイドブックの順に呼ばれること
- OFF にしたカテゴリのオーケストレーターが呼ばれないこと
- 3 カテゴリへ同一の `sessionId` と同一の `CancellationToken` が渡されること
- 実行時上書きした `settings`(翻訳モード・プロバイダー・モデル)が各オーケストレーターへ渡ること
- 1 カテゴリが例外を投げても後続カテゴリが実行されること
- 全カテゴリ完了後に統合サマリーが 1 回書き出され、3 カテゴリの項目がすべて含まれること
- キャンセル時にも統合サマリーが書き出され、後続カテゴリが開始されないこと
- カテゴリ別進捗と全体進捗が正しく合算されること
- 失敗対象だけに絞った再試行計画が組み立てられ、新しい `sessionId` で実行されること。MODはJAR相対パスで一意に絞られること

**リソースパック出力**

- `pack_format` を渡した場合に `pack.mcmeta` へその値が出力されること
- 省略した場合に `9` が出力されること(既存テストの維持)

**画面(features)**

- カテゴリ 0 件のときチェックボックスが無効化されること
- 全カテゴリ OFF のとき `[すべて翻訳]` が無効化されること
- API キー未設定時に日本語のエラーメッセージが表示され実行されないこと
- `[すべて翻訳]` で翻訳前サマリーが表示され、「戻る」で実行されないこと
- 完了画面に成功・失敗・スキップの件数と `[失敗した項目を再試行]` が表示されること

リリース前に次を順番に実行し、すべて成功させること。

```powershell
flutter pub get
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test
flutter build windows --release
```

## 要検証項目

次の項目は公式資料で確定できていない。実装時に確認し、相違があれば本仕様と実装の既定値を更新する。本書の基本方針(既存オーケストレーターの再利用、実行時設定の非永続化、部分失敗の継続、後方互換のフォールバック)はその場合も維持する。

- Minecraft バージョンと `pack_format` の対応表の各境界値。特に 1.19.3 以降は同一マイナーバージョン内でも値が変わるため、Minecraft の公式資料で確定させる。
- 1.21.1 より新しいバージョンの `pack_format`。対応表の更新方針(値をハードコードするか、`supported_formats` を併用するか)。
- 1.20.2 以降、`pack_format` が一致しないリソースパックが既定で非表示になる挙動の詳細と、それが翻訳結果の表示に与える影響。
- 統合サマリーの書き直しが、既存の履歴画面(`HistoryDialog`)の表示で問題なく扱えること(4 種別が混在する `items` の表示)。

## 今後の検討事項

- `pack.mcmeta` の `supported_formats`(対応 `pack_format` の範囲指定)を併用し、バージョン判定の誤差に対する耐性を高めることを別要件として検討する。
- カテゴリの並列実行は、API のレート制限(HTTP 429)への影響が大きいため本仕様では行わない。必要になれば同時実行数の制御と合わせて別要件として検討する。
- 翻訳コスト(概算料金)の表示は、プロバイダーごとの料金体系を保持する必要があるため別要件として検討する。
- 複数インスタンスをまとめて翻訳するキュー機能は、本仕様の `InstanceTranslationPlan` を要素とするキューとして後から追加できる構成とし、別要件として検討する。
