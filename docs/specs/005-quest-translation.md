# 005: クエスト翻訳機能(FTB Quests / Better Quests)

## 目的

1つのタブで FTB Quests(SNBT / KubeJS lang)と Better Quests(JSON / .lang)という2つの独立したクエスト形式を検出・翻訳する。SNBT 直接編集は原本を直接上書きするためデータ破損リスクが MOD 翻訳より高く、バックアップの受け入れ条件を必須とする。

参照: `../feature-spec.md` §7(クエスト翻訳機能)、§16.4(FTB Quests KubeJS 出力先の設計判断・実機確認事項)。

## 設計判断: FTB Quests(KubeJS)の翻訳結果出力先

旧 `docs/spec.md` は `kubejs/assets/kubejs/lang/{targetLanguage}.json` と `kubejs/assets/ftbquests/lang/{targetLanguage}.json` の2箇所への出力を設計意図として明記していたが、旧実装の実コードは前者にしか書き込んでいなかった。これは**旧実装側の不備(設計意図の未実装)**と判断し、Villager Translator では設計意図どおり**両方のパスへ出力する**方針を採用する。誤ったパスにのみ出力すると「翻訳ファイルは生成されるがゲーム内表示に反映されない」致命的な不具合になり得るため、片方のみへの出力は選択しない。

**要注意(実機確認が必要)**: 上記は設計意図に基づく方針決定であり、FTB Quests / KubeJS Localization が実際にどちらのパスから翻訳文字列を読み込むかは未検証のままである。念のため、本機能の実装後(またはリリース前)に実際の Minecraft 環境(FTB Quests + KubeJS 導入インスタンス)でゲーム内表示を目視確認し、両パスへの出力で問題なく翻訳が反映されることを確認する。確認の結果、片方のパスが不要・有害と判明した場合は本仕様を更新する。

## 対象範囲

### FTB Quests(feature-spec.md §7.1)

- **KubeJS 経由**: `{プロファイル}/kubejs/assets/kubejs/lang/en_us.json` が存在する場合、そのディレクトリ内の `*.json` を対象とする(既に翻訳済みファイル名パターンは除外)。
- 出力先は上記「設計判断」のとおり `kubejs/assets/kubejs/lang/{targetLanguage}.json` と `kubejs/assets/ftbquests/lang/{targetLanguage}.json` の**両方**に書き込む。
- **SNBT 直接編集**: KubeJS lang が存在しない場合、`config/ftbquests/quests`(標準)→ `config/ftbquests/normal`(FTB Interactions Remastered 用)→ `config/ftbquests`(フォールバック)の順に存在するディレクトリを探し、配下の `*.snbt` を再帰的に列挙する。
- SNBT からの翻訳対象文字列抽出は `title` `subtitle` `description` の値を正規表現で抽出する方式とする(エスケープされた `"` は前方のバックスラッシュ数で判定)。
- SNBT ファイルは翻訳後、同じファイルに直接上書きする(言語サフィックスを付けない)。
- 翻訳前に選択した SNBT ファイルをセッションディレクトリへバックアップする(`logs/localizer/{sessionId}/backup/snbt_original/`)。
- SNBT の内容種別(`json_keys` / `direct_text`)判定ロジックは実装しない。`title`/`subtitle`/`description` の正規表現抽出のみで完結させる。

### Better Quests(feature-spec.md §7.2)

- 標準: `{プロファイル}/resources/betterquesting/lang/*.json`(非再帰)。
- 直接: `{プロファイル}/config/betterquesting/DefaultQuests.lang`(単一ファイル)。
- 出力: 標準形式は `{basename}.{targetLanguage}.json` を同ディレクトリに新規作成。直接形式は `DefaultQuests.{targetLanguage}.lang` を新規作成。原本は変更しない。
- `.lang` はキー=値形式のためソート済み `key=value` 行として再シリアライズする。

### 共通事項(feature-spec.md §7.3)

- クエストはファイル全体を1つの翻訳単位として LLM に渡す(キー単位分割はしない)。SNBT はテキスト全体を、JSON/LANG は変換した JSON 文字列全体を送信し、応答をそのまま構造に戻す。
- 既存翻訳の判定: SNBT は常に未翻訳扱い(直接上書きのため判定不能、常に全文再翻訳)。JSON/LANG(KubeJS lang、Better Quests 標準/直接)は隣接する `{stem}.{lang}.json` の有無で判定し、`003` の差分更新ロジックの対象とする。

## 対象外

- MOD・Patchouli・カスタムファイルのスキャン・翻訳(`004`、`006`、`007` で扱う)。
- 進捗表示・キャンセル・ログ・履歴の横断的な UI 統合(`008` で扱う)。
- FTB Interactions Remastered 固有の追加検出パス以外の、他クエスト MOD への対応拡張。

## 受け入れ条件

1. `kubejs/assets/kubejs/lang/en_us.json` が存在するテスト用ディレクトリに対しスキャンを実行すると、同ディレクトリ内の `*.json`(翻訳済みファイル名パターンを除く)が KubeJS lang 対象として検出されることを検証する。
2. KubeJS lang の翻訳結果が `kubejs/assets/kubejs/lang/{targetLanguage}.json` と `kubejs/assets/ftbquests/lang/{targetLanguage}.json` の両方に、同一内容で正しく書き込まれることを検証する。
3. `kubejs/assets/kubejs/lang/en_us.json` が存在しない場合、`config/ftbquests/quests` → `config/ftbquests/normal` → `config/ftbquests` の順に存在する最初のディレクトリ配下の `*.snbt` が再帰的に検出されることを検証する。
4. SNBT ファイルから `title` `subtitle` `description` の値が正規表現で正しく抽出されることを、エスケープされた `"` を含むケースを含めて検証する。
5. SNBT 翻訳後、同一ファイルが翻訳結果で上書きされ、言語サフィックス付きの別ファイルが作成されないことを検証する。
6. SNBT 翻訳前に、対象ファイルが `logs/localizer/{sessionId}/backup/snbt_original/` へバックアップされることを検証する(翻訳失敗時にも原本相当がバックアップから復元可能であることを含む)。
7. `resources/betterquesting/lang/*.json` の各ファイルに対し、翻訳結果が `{basename}.{targetLanguage}.json` として同ディレクトリに新規作成され、原本が変更されないことを検証する。
8. `config/betterquesting/DefaultQuests.lang` に対し、翻訳結果が `DefaultQuests.{targetLanguage}.lang` として新規作成され、原本が変更されないことを検証する。
9. `.lang` 形式の出力が `key=value` 形式でキーのソート順に再シリアライズされることを検証する。
10. SNBT 以外(KubeJS lang、Better Quests 標準/直接)のクエスト翻訳が、隣接する `{stem}.{lang}.json` の有無に応じて `003` の差分更新ロジック(スキップ/差分更新/全て再翻訳)を正しく適用することを検証する。
11. SNBT の既存翻訳判定が常に「未翻訳扱い」となり、「既存翻訳の扱い」設定に関わらず常に全文が再翻訳されることを検証する。
12. クエストファイル(SNBT・JSON/LANG いずれも)がファイル全体で1つの翻訳単位として LLM アダプターに渡され、キー単位に分割されないことを検証する。
13. `flutter analyze` / `flutter test` が成功する。
14. (実機確認・自動テスト対象外)本機能のリリース前に、FTB Quests + KubeJS を導入した Minecraft インスタンスで実際に翻訳を実行し、ゲーム内のクエスト表示に翻訳結果が反映されることを目視確認する。確認結果(反映されたパス、問題があれば内容)を本仕様または実装コミットに記録する。

## 移行上の判断

- SNBT のコンテンツ種別判定ロジック(`json_keys` / `direct_text`)は、旧実装で実際の出力ロジックに使われていなかった未配線コードであるため実装しない(feature-spec.md §7.3、§16.2)。
- FTB Quests(KubeJS)の出力先は、旧実装ではなく旧 `docs/spec.md` の設計意図(2箇所出力)を正とし、両方のパスへ出力する(feature-spec.md §16.4)。ただし実機での動作確認がまだのため、実装後に FTB Quests + KubeJS 導入環境での目視確認を別途行う(上記「設計判断」参照)。
