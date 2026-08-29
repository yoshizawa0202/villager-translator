# 011: Minecraft ランチャー・インスタンス自動検出

- 文書番号: 011
- 文書名: Minecraft ランチャー・インスタンス自動検出
- 更新日: 2026-08-24
- ステータス: 実装済み(静的解析・テスト・Windows Release ビルド検証済み)
- 対象アプリケーション: VillagerTranslator

## 目的

Windows 上にインストールされた主要 Minecraft ランチャーのインスタンスを自動検出し、利用者が Minecraft のフォルダ構成やランチャーごとの保存場所を理解していなくても Villager Translator を利用できるようにする。

現在は利用者が Minecraft プロファイルのフォルダを手動で探し、テキスト入力または「参照」ボタンで指定する必要がある。本仕様は、その手前に「ランチャー検出 → インスタンス選択 → 翻訳対象の自動解析」という導線を追加する。

参照: `../feature-spec.md` §1.4(想定ディレクトリ構成)、§3(画面構成・共通 UI フロー)、§6.1(MOD スキャン)、§7(クエスト翻訳機能)、§8.1(Patchouli スキャン)、`004-mod-translation.md`、`005-quest-translation.md`、`006-patchouli-translation.md`、`008-progress-log-history.md`。issue #18。

インスタンス単位の一括翻訳は本仕様の対象外とし、`012-instance-batch-translation.md` で扱う。

## 対象範囲

### 1. Minecraft インスタンス共通モデル

ランチャー固有の情報を翻訳処理へ直接渡さないため、共通モデル `MinecraftInstance` を追加する。

`lib/domain/minecraftinstance/minecraft_instance.dart`

```dart
class MinecraftInstance {
  final String id;
  final String name;
  final MinecraftLauncher launcher;
  final String rootPath;
  final String? minecraftVersion;
  final ModLoader modLoader;
  final String? modLoaderVersion;
  final String? iconPath;
  final DateTime? lastPlayed;
}
```

- `rootPath` は **`mods/` `config/` `saves/` が直下にある Minecraft ルート**の絶対パスとする。Prism Launcher のようにインスタンスフォルダ配下の `.minecraft/` が実体である場合、`rootPath` にはインスタンスフォルダではなく `.minecraft/` を格納する。既存の翻訳機能はすべてこのディレクトリを基準に動作する。
- `id` は検出元と正規化済み絶対パスから導出する安定 ID とし、再検出しても同じインスタンスには同じ値が付く。
- `minecraftVersion` および `modLoaderVersion` は取得できない場合 `null` とし、UI では `Unknown` と表示する。
- `modLoader` は取得できない場合 `ModLoader.unknown` とする。

ランチャー種別および Mod Loader 種別は次のとおりとする。

`lib/domain/minecraftinstance/minecraft_launcher.dart`

```dart
enum MinecraftLauncher { official, prism, curseForge, atLauncher, modrinth, manual }
```

`lib/domain/minecraftinstance/mod_loader.dart`

```dart
enum ModLoader { vanilla, forge, neoForge, fabric, quilt, unknown }
```

### 2. ランチャー検出の全体構造

検出処理はランチャーごとに分離し、共通のインターフェースで束ねる。

```text
LauncherDiscoveryService
│
├─ OfficialLauncherDetector
├─ PrismLauncherDetector
├─ CurseForgeLauncherDetector
├─ ATLauncherDetector
└─ ModrinthLauncherDetector
```

`lib/infrastructure/minecraftinstance/launcher_detector.dart`

```dart
abstract class LauncherDetector {
  MinecraftLauncher get launcher;
  Future<List<MinecraftInstance>> discoverInstances();
}
```

`LauncherDiscoveryService` は全 Detector を実行し、結果を重複排除・整列して返す。

### 3. 検索の優先順位

PC 内の全フォルダを毎回総当たりで検索しない。次の順に検索する。

1. 既知の標準パス
2. ランチャー設定ファイルから取得したカスタム保存先
3. 利用者が登録した追加パス(手動インスタンス追加、後述)

これらで 1 件も見つからなかった場合に限り、一覧画面から「PC 内を詳しく検索」を任意に実行できるようにする(後述)。

### 4. 環境変数・ドライブ列挙の境界

`%APPDATA%`、`%LOCALAPPDATA%`、`%USERPROFILE%` およびドライブ一覧の取得は、注入可能な抽象 `WindowsEnvironment`(`lib/infrastructure/minecraftinstance/windows_environment.dart`)越しに行う。

これにより、実際のランチャーをインストールしていない環境および Windows 以外の CI 上でも、一時ディレクトリへ再現したフォルダ構造に対して検出処理を検証できる。

### 5. Minecraft Launcher(公式)

標準ディレクトリを確認する。

```text
%APPDATA%\.minecraft
```

次のランチャー設定ファイルを解析する。

```text
%APPDATA%\.minecraft\launcher_profiles.json
%APPDATA%\.minecraft\launcher_profiles_microsoft_store.json
```

`profiles` 配下の各 Installation について、次を取得する。

| 取得対象 | 取得元 |
|---|---|
| インスタンス名 | `name`(空の場合は `lastVersionId`) |
| ルートパス | `gameDir`(未指定なら `%APPDATA%\.minecraft`) |
| Minecraft バージョン | `lastVersionId` から解析 |
| Mod Loader / バージョン | `lastVersionId` から解析 |
| 最終起動日時 | `lastUsed` |
| アイコン | `icon`(データ URI 形式は使用しない) |

Installation ごとに独自の `gameDir` が指定されている場合、そのディレクトリも独立した Minecraft インスタンスとして検出する。

```text
Minecraft Launcher
├─ Latest Release
│  └─ %APPDATA%\.minecraft
├─ NeoForge 1.21.1
│  └─ D:\Minecraft\NeoForge1211
└─ Fabric 1.21.1
   └─ D:\Minecraft\Fabric1211
```

`lastVersionId` からの解析は次の規則とする(照合は大文字小文字を無視する)。

| `lastVersionId` の例 | Minecraft | Mod Loader | Loader バージョン |
|---|---|---|---|
| `1.21.1` | `1.21.1` | `vanilla` | `null` |
| `neoforge-21.1.72` | `null`(※) | `neoForge` | `21.1.72` |
| `1.20.1-forge-47.2.20` | `1.20.1` | `forge` | `47.2.20` |
| `fabric-loader-0.16.9-1.21.1` | `1.21.1` | `fabric` | `0.16.9` |
| `quilt-loader-0.26.4-1.21.1` | `1.21.1` | `quilt` | `0.26.4` |

※ NeoForge の ID は Minecraft バージョンを含まないため、後述のメタデータ多段フォールバックで補う。解決できない場合は `null`(`Unknown`)のままとする。

### 6. Prism Launcher

標準パスを確認する。

```text
%APPDATA%\PrismLauncher
%APPDATA%\PrismLauncher\instances
```

ランチャー設定ファイル `prismlauncher.cfg`(INI 形式)を解析し、`InstanceDir` が設定されていればそのディレクトリを実際のインスタンス保存先として使用する。相対パスの場合はランチャールートからの相対として解決する。

次にも対応する。

- Portable 版(実行ファイルと同じ階層に `prismlauncher.cfg` と `instances/` が存在する構成)
- カスタム Launcher Root
- カスタム Instance Directory
- 別ドライブに配置された Prism 環境

Portable 版およびカスタム Launcher Root は、利用者が登録した追加パスをランチャールート候補として扱うことで対応する。追加パス直下に `prismlauncher.cfg` または `instances/` があれば Prism 環境と判定する。

インスタンス 1 件あたり次を解析する。

| ファイル | 取得対象 |
|---|---|
| `{instance}/instance.cfg` | インスタンス名(`name`)、最終起動日時(`lastLaunchTime`、ミリ秒エポック) |
| `{instance}/mmc-pack.json` | `components` 配列から Minecraft バージョンと Mod Loader |
| `{instance}/.minecraft` または `{instance}/minecraft` | Minecraft ルート |

`mmc-pack.json` の `components[].uid` と Mod Loader の対応は次のとおりとする。

| `uid` | 意味 |
|---|---|
| `net.minecraft` | Minecraft バージョン(`version`) |
| `net.minecraftforge` | Forge |
| `net.neoforged` | NeoForge |
| `net.fabricmc.fabric-loader` | Fabric |
| `org.quiltmc.quilt-loader` | Quilt |

Minecraft ルートは `.minecraft` を優先し、存在しなければ `minecraft`(旧構成)を使用する。どちらも存在しない場合はインスタンスフォルダ自体を候補としてインスタンス検証にかける。

### 7. CurseForge

標準的な Minecraft Modding Folder を確認する。

```text
%USERPROFILE%\curseforge\minecraft
%USERPROFILE%\curseforge\minecraft\Instances
```

CurseForge は Modding Folder を変更できるため、標準パスだけに依存しない。CurseForge の設定ファイルから実際の Modding Folder を取得できる場合はそれを優先する(設定ファイル名およびキー名は「要検証項目」を参照)。設定から取得できない場合は標準パスへフォールバックする。

インスタンス 1 件あたり `{instance}/minecraftinstance.json` を解析する。

| 取得対象 | 取得元 |
|---|---|
| インスタンス名 | `name` |
| Minecraft バージョン | `gameVersion` |
| Mod Loader / バージョン | `baseModLoader.name`(例 `forge-47.2.20`)または `baseModLoader.forgeVersion` |
| 最終起動日時 | `lastPlayed` |

CurseForge のインスタンスフォルダは直下が Minecraft ルート(`mods/` `config/` `saves/` が直下にある)であるため、`rootPath` はインスタンスフォルダ自体とする。

### 8. ATLauncher

ATLauncher のデータディレクトリを検出する。標準パスは次を確認する。

```text
%APPDATA%\ATLauncher
%APPDATA%\ATLauncher\instances
```

次の構造を対象とする。

```text
ATLauncher/
└─ instances/
   ├─ InstanceA/
   ├─ InstanceB/
   └─ InstanceC/
```

固定パスだけに依存せず、次を考慮する。

- 通常インストール版
- Portable 版
- 別ドライブへの配置
- カスタム保存先

Portable 版・カスタム保存先は、Prism と同様に「利用者が登録した追加パスをランチャールート候補として扱う」方式で対応する。追加パス直下に `instances/` があれば ATLauncher 環境と判定する。

インスタンス 1 件あたり `{instance}/instance.json` を解析する。

| 取得対象 | 取得元 |
|---|---|
| インスタンス名 | `launcher.name`(取得できない場合はフォルダ名) |
| Minecraft バージョン | `id` |
| Mod Loader / バージョン | `launcher.loaderVersion.type` と `launcher.loaderVersion.version` |

ATLauncher のインスタンスフォルダは直下が Minecraft ルートであるため、`rootPath` はインスタンスフォルダ自体とする。

### 9. Modrinth App

次を検出対象とする。

```text
%APPDATA%\ModrinthApp
%APPDATA%\ModrinthApp\profiles
```

旧バージョンとの互換性のため、次も確認する。

```text
%APPDATA%\com.modrinth.theseus
%APPDATA%\com.modrinth.theseus\profiles
```

Modrinth App はインスタンス構成を SQLite データベース(`app.db`)に保持する。本仕様ではこのデータベースを読まない(理由は「設計判断」参照)。`profiles/` 配下のディレクトリを列挙し、後述のインスタンス検証とメタデータ多段フォールバックによって `MinecraftInstance` を構築する。

- インスタンス名: プロファイルのディレクトリ名
- Minecraft バージョン / Mod Loader: メタデータ多段フォールバックで取得。取得できない場合は `Unknown`

Modrinth App 側でデータ保存先(App directory)が変更されている場合は、利用者が登録した追加パスをランチャールート候補として扱うことで対応する。追加パス直下に `profiles/` があれば Modrinth 環境と判定する。

Modrinth のプロファイルフォルダは直下が Minecraft ルートであるため、`rootPath` はプロファイルフォルダ自体とする。

### 10. インスタンス検証

フォルダが存在するだけでは Minecraft インスタンスと判定しない。次の 2 段階で判定する。

**確定判定**: ランチャー固有メタデータが読み取れた場合は、その 1 件だけでインスタンスとして確定する。

- `instance.cfg` と `mmc-pack.json` の組(Prism)
- `minecraftinstance.json`(CurseForge)
- `instance.json`(ATLauncher)
- `launcher_profiles.json` の Installation エントリ(公式)

**マーカー判定**: メタデータが無い場合(Modrinth、手動追加、詳細検索の結果)は、対象ディレクトリ直下に次のマーカーがいくつ存在するかを数え、**2 つ以上**該当する場合にインスタンスとして扱う。

```text
mods/
config/
resourcepacks/
saves/
options.txt
logs/
```

判定は純粋関数 `lib/domain/minecraftinstance/instance_validator.dart` に置き、実ファイルシステムへのアクセス(マーカー集合の収集)は infrastructure 層が担当する。

### 11. 重複排除

複数の Detector が同じインスタンスを検出した場合、一覧に重複表示しない。

重複判定キーは `rootPath` を正規化した絶対パスとする。正規化は次を行う。

1. 絶対パスへ解決する
2. 可能なら `resolveSymbolicLinks()` を試み、失敗した場合は正規化のみで続行する
3. 末尾のパスセパレータを除去する
4. Windows のため、比較時は大文字小文字を区別しない

正規化は `resolveSymbolicLinks()` を伴うため実ファイルシステムへアクセスする処理であり、各 Detector が `MinecraftInstance` を組み立てる時点(infrastructure 層、`lib/infrastructure/minecraftinstance/launcher_detector.dart` の `normalizeInstancePath()`)で行う。重複排除自体(`lib/domain/minecraftinstance/instance_deduplicator.dart`)は、既に正規化済みの `rootPath` 文字列を大文字小文字を無視して比較するだけの純粋関数とする。

名前が同一でも実体パスが異なる場合は、別インスタンスとして両方を保持する。

```text
Prism Launcher / Prominence II       → D:\PrismLauncher\instances\PromII\.minecraft
CurseForge     / Prominence II       → C:\Users\user\curseforge\minecraft\Instances\Prominence II
```

同一パスが複数の Detector から得られた場合、先に検出された側を基準(`base`)として採用し、`base` の `name`・`launcher`・`id` を維持したまま、`base` 側が `null` または `ModLoader.unknown` のフィールド(`minecraftVersion`・`modLoader`・`modLoaderVersion`・`iconPath`)だけを後続の検出結果で補完する。`lastPlayed` は両者のうち新しい方を採用する。

この「先着優先」が実質的に「メタデータ確定判定を行った Detector を優先する」結果になるように、`LauncherDiscoveryService.buildDefaultDetectors()`(`lib/infrastructure/minecraftinstance/launcher_discovery_service.dart`)は Detector をランチャー固有メタデータで確定判定できるもの(公式 / Prism / CurseForge / ATLauncher)を先に、単独では確定判定を持たないもの(Modrinth / 手動追加)を後に並べる。ただし `MinecraftInstance` 自体は「その検出が確定判定によるものか」を示すフラグを保持しないため、この優先順は Detector の実行順序のみに依存する。特定のインスタンスについて、先に実行された Detector がそのインスタンスの確定判定に失敗し(メタデータ破損などでマーカー判定へフォールバックし)、後から実行された Detector が同じパスを確定判定できた場合でも、`base` は変わらず先に実行された側のままになる。

重複排除は純粋関数 `lib/domain/minecraftinstance/instance_deduplicator.dart` に置く。正規化(実ファイルシステムアクセスを伴う)はこの関数の外側、Detector 側の責務とする。

### 12. Minecraft バージョン・Mod Loader の多段フォールバック

各 Detector がランチャーメタデータから値を取得できなかった場合、次の順に補完を試みる。

1. ランチャーメタデータ(第 5〜9 節)
2. `{rootPath}/logs/latest.log` の起動時ログ行から Minecraft バージョンおよび Loader を抽出する
3. `{rootPath}/mods/` 内の JAR に含まれる `fabric.mod.json` の `depends.minecraft`、または `META-INF/mods.toml` の `[[dependencies]]` 宣言から Minecraft バージョン範囲を推定する(既存の `lib/domain/modtranslation/mod_info_extractor.dart` と `lib/infrastructure/modtranslation/jar_reader.dart` を再利用する)

いずれでも取得できない場合は `minecraftVersion` を `null`、`modLoader` を `ModLoader.unknown` とし、UI では `Unknown` と表示する。

3 の推定は JAR の読み取りを伴うため、一覧表示時には実行しない。インスタンス選択後の自動解析(第 16 節)の中で、既に読み込んだ JAR の情報から補完する。

### 13. インスタンス一覧画面(起動時ホーム画面)

Minecraft インスタンスを一覧表示する画面 `InstanceListPage` を追加し、アプリの起動時ホーム画面とする。

```text
Minecraftインスタンス

────────────────────────

Prism Launcher

Prominence II
Minecraft 1.20.1
Fabric
MOD 286個

[翻訳する]

────────────────────────

CurseForge

Better MC
Minecraft 1.20.1
Forge
MOD 238個

[翻訳する]
```

- `lib/main.dart` の `home:` を `InstanceListPage` へ変更する。
- 「翻訳する」を押すと、そのインスタンスの解析結果画面(第 16 節)へ遷移する。
- 既存の 4 タブ統合シェル `MainShellPage` は削除せず、解析結果画面から遷移できるようにする。遷移時は `MinecraftInstance.rootPath` を既存の `ProfileDirectoryController.setPath()` へ渡し、4 タブすべてがそのディレクトリを対象として動作する状態にする。
- `MainShellPage` には表示用の任意パラメータ `MinecraftInstance? instance` を追加し、指定された場合は AppBar にインスタンス名・Minecraft バージョン・Mod Loader を表示する。既存のコンストラクタ引数はすべて省略可能のまま維持する。
- MOD 件数は一覧表示時点では `{rootPath}/mods/*.jar` のファイル数のみを数え、JAR の中身は開かない。翻訳可能 MOD 件数は自動解析(第 16 節)で確定する。

### 14. 検索・フィルター

一覧画面に、ランチャー別フィルターとインスタンス名検索を追加する。

```text
すべて / Minecraft / Prism / CurseForge / ATLauncher / Modrinth
```

インスタンス名の部分一致検索(大文字小文字を区別しない)に対応する。

フィルターと検索の適用は、既存 MOD タブ(`lib/features/mod_translation/mod_translation_controller.dart` の `visibleEntries`)と同じく、コントローラー側で表示用の一覧を導出する形とする。

並び順は「最終起動日時の降順 → インスタンス名の昇順」とし、`lastPlayed` が取得できないインスタンスは名前順で末尾に並べる。

### 15. 手動追加・再検出・詳細検索・最近使用

#### 15.1 手動インスタンス追加

自動検出だけに依存しない。一覧画面に `[インスタンスを手動追加]` を設ける。

用途は次を想定する。

- カスタム Launcher
- Portable 環境
- 独自 Minecraft 環境
- 自動検出できなかったインスタンス
- サーバーパック等のローカル環境

追加されたパスは次のように扱う。

- 追加パス自体がインスタンス検証を満たす場合、`MinecraftLauncher.manual` のインスタンスとして登録する。
- 追加パス直下に `instances/` `profiles/` `prismlauncher.cfg` のいずれかがある場合、対応する Detector のランチャールート候補として扱い、配下のインスタンスを検出する。
- 追加パスは永続化し、次回起動時にも検索対象とする。
- 追加時にインスタンス検証を満たさず、ランチャールートとしても解釈できない場合は、日本語のエラーメッセージを表示して登録しない。

#### 15.2 再検出

一覧画面に `[再検出]` を設ける。新しく MOD パックをインストールした場合などに、アプリを再起動せず再スキャンできるようにする。

#### 15.3 詳細検索

通常の自動検出では、標準保存先・ランチャー設定・登録済みカスタムパスのみを検索する。PC 内の全ドライブを毎回再帰検索しない。

自動検出で 1 件も見つからなかった場合に限り、次を提示する。

```text
インスタンスが見つかりませんか？

[PC内を詳しく検索]
```

詳細検索は次の制約のもとで実行する。

- 全固定ドライブのルートから再帰探索する
- ルートからの深さ上限を設ける(既定 6 階層)
- 既定の除外ディレクトリ(`Windows`、`Program Files`、`Program Files (x86)`、`ProgramData`、`$Recycle.Bin`、`System Volume Information`、`node_modules`、`.git`)配下へは降りない
- インスタンスと判定したディレクトリ配下へはそれ以上降りない
- 実行中は進捗(探索中のパス)を表示し、既存の `CancellationToken`(`lib/domain/common/cancellation_token.dart`)でキャンセルできる
- アクセス権限エラーはそのディレクトリのみスキップし、探索全体を中断しない

#### 15.4 最近使用したインスタンス

最後に利用した Minecraft インスタンスを保存し、次回起動時に一覧上部へ表示して素早く再開できるようにする。

```text
最近使用

Prominence II
Prism Launcher

[開く]
```

保存件数は最大 5 件とし、古いものから破棄する。保存済みインスタンスの `rootPath` が存在しなくなっている場合は「見つかりません」と表示し、一覧からの削除操作を提供する。

#### 15.5 永続化

手動追加パスと最近使用インスタンスは、プロファイル非依存のアプリケーションサポートディレクトリ(`getApplicationSupportDirectory()`、`lib/main.dart` で解決済み)配下の `instances.json` へ保存する。

`settings.json`(`lib/infrastructure/settings/settings_repository.dart`)へは混ぜない。API キーはこのファイルにも保存しない。

ファイルが存在しない・壊れている場合は例外を投げず、空の状態として扱う(既存 `SettingsRepository.load()` と同じ方針)。

書き込みは一時ファイルへ書いてからリネームする原子的書き込みとし、書き込み途中でプロセスが終了しても `instances.json` が破損しないようにする。手動パスの追加と最近使用の記録は短時間に連続して起こり得るため、呼び出しを直列化する(既存 `SettingsRepository.save()` と同じ方針)。

### 16. インスタンス選択後の自動解析

インスタンスを選択した時点で、その Minecraft 環境を自動スキャンし、結果を表示する。

```text
Prominence II

Minecraft   1.20.1
Loader      Fabric

MOD         286個
翻訳可能MOD  194個

Quest       FTB Quests 検出
Guidebook   Patchouli 23冊
```

スキャンには既存のスキャナをそのまま再利用し、新しいスキャン処理を追加しない。

| 対象 | 再利用する処理 |
|---|---|
| MOD | `lib/infrastructure/modtranslation/mod_directory_scanner.dart` の `scanModsDirectory()` |
| クエスト | `lib/infrastructure/questtranslation/quest_directory_scanner.dart` の `scanQuestsDirectory()` |
| ガイドブック | `lib/infrastructure/patchoulitranslation/patchouli_directory_scanner.dart` の `scanPatchouliBooksDirectory()` |

クエストの検出結果は形式別に表示する。

```text
クエスト

✓ FTB Quests
  328クエスト

－ Better Quests
  未検出
```

ガイドブックは MOD とブック名を表示する。

```text
ガイドブック

Ars Nouveau
└─ Worn Notebook

Malum
└─ Encyclopedia Arcana
```

翻訳済み・未翻訳の内訳は、各スキャン結果が既に持つ `hasExistingTranslation`(`ModScanEntry`、`PatchouliBookEntry`)から集計する。新しい判定ロジックは追加しない。

```text
翻訳可能MOD  194
翻訳済み      73
未翻訳       121
```

解析は時間がかかるため、進捗表示とキャンセルに対応する。解析中に対象インスタンスが削除されていた場合は、日本語のエラーメッセージを表示して一覧へ戻る。

### 17. 既存機能との互換性

次の既存機能は削除しない。新しいインスタンス検出は、既存機能を利用した上位機能として追加する。

- MOD 個別翻訳
- クエスト個別翻訳
- Patchouli 個別翻訳
- カスタムファイル翻訳
- プロファイルフォルダの手動指定
- 差分更新
- バックアップ
- 翻訳履歴

`MainShellPage` のプロファイルディレクトリ入力欄と「参照」ボタンは維持し、インスタンス一覧を経由せずに従来どおり利用できる状態を保つ。

## 対象外

次の内容は本仕様の対象外とする。

- インスタンス単位の一括翻訳(`012-instance-batch-translation.md` で扱う)
- お気に入り登録機能(issue #18 でも「任意機能」と位置づけられているため、別要件として検討する)
- MultiMC、GDLauncher など初期対応 5 ランチャー以外の検出
- Modrinth App の SQLite データベース(`app.db`)の読み取り
- ランチャーの起動、インスタンスの作成・削除・複製などランチャー機能の代替
- Minecraft サーバーインスタンスの専用対応(手動追加による汎用対応にとどめる)
- Windows 以外のプラットフォームでのランチャー検出

## 設計判断

### 既存の翻訳機能を改造しない

既存の 4 機能(MOD / クエスト / Patchouli / カスタムファイル)は、いずれも「プロファイルディレクトリ 1 つ」を基準に組まれている。インスタンス選択は `MinecraftInstance.rootPath` を既存の `ProfileDirectoryController.setPath()` へ渡すだけで完結するため、スキャナ・オーケストレーター・翻訳サービスには一切変更を加えない。

これは issue #18 の「Launcher 固有処理を MOD 翻訳・クエスト翻訳・Patchouli 翻訳側に追加しない」という要求に対応する。ランチャー固有の知識は Detector の内側に閉じ、境界は `MinecraftInstance` のみとする。

### ランチャー設定のパーサーを domain 層の純粋関数にする

`launcher_profiles.json`、`prismlauncher.cfg`、`mmc-pack.json`、`minecraftinstance.json`、`instance.json` の解析は、いずれも「文字列 → モデル」の純粋な変換として `lib/domain/minecraftinstance/launcher_metadata/` に置く。実ファイルシステムへのアクセスは infrastructure 層の Detector が担当する。

これは既存の `mod_scanner.dart`(純粋)と `mod_directory_scanner.dart`(`dart:io`)の分離と同じ形であり、実際のランチャーをインストールしていない環境でも解析ロジックを単体テストできるようにするため。

### Modrinth App の SQLite データベースを読まない

Modrinth App はインスタンス構成を SQLite データベースに保持する。これを読むには新たなネイティブ依存(`sqlite3` 等)の追加が必要になり、Windows Release ZIP の同梱 DLL が増え、`010-additional-llm-providers.md` AC-19 の配布要件へ影響する。

また、データベーススキーマはアプリ側の内部実装であり、公開された互換性保証が無い。破壊的変更が起きた場合に検出が壊れるリスクを、翻訳アプリが負う理由が無い。

このため `profiles/` 配下のディレクトリ列挙とインスタンス検証にとどめ、取得できないメタデータは `Unknown` として扱う。issue #18 の「取得できない場合は Unknown として扱う」方針と整合する。

### インスタンス判定をマーカーのスコアリングにする

単一のマーカー(例: `mods/` だけ)で判定すると、MOD 配布用の作業フォルダやバックアップフォルダを誤検出する。逆に全マーカーを必須にすると、`saves/` がまだ無い新規インスタンスや、`logs/` を削除した環境を取りこぼす。

このため 2 つ以上の一致を条件とし、ランチャーメタデータが読み取れた場合はそれ単独で確定とする二段構成にする。

### 重複排除に正規化済み絶対パスを使う

同じ Minecraft ルートを公式ランチャーの `gameDir` と手動追加パスの両方から検出することは通常に起こる。実体で比較しなければ重複表示になる。

一方で、名前は実体を特定しない。異なるランチャーで同じ modpack を導入していれば同名インスタンスが並ぶが、これらは別環境であり両方翻訳できなければならない。このため名前は重複判定に使わない。

### ランチャー設定の破損でアプリ全体を止めない

1 つのランチャー設定ファイルが壊れていても、他のランチャーの検出とアプリ全体の起動は継続する。各 Detector は自身の解析失敗を捕捉して空リストを返し、例外を呼び出し元へ伝播させない。

これは既存スキャナ(`quest_directory_scanner.dart`、`mod_directory_scanner.dart`)の「壊れたファイルはスキップし、他のファイルのスキャンを継続する」方針と同じである。

### PC 内の全ドライブ再帰検索を既定にしない

全ドライブの再帰検索は、環境によって数分単位の時間とディスク I/O を要する。起動のたびに実行すると、検出のために起動が遅いアプリになる。

このため既定は「標準パス → ランチャー設定 → 登録済みカスタムパス」の 3 段階に限定し、詳細検索は 1 件も見つからなかった場合の明示的な操作としてのみ提供する。

### 永続化先を settings.json と分ける

`SettingsRepository` は「API キーを含まないアプリケーション設定」専用として役割が確立しており、自動保存の競合を防ぐための直列化ロックを備えている。手動追加パスや最近使用インスタンスは更新契機も寿命も異なるため、同じファイル・同じ保存経路を共有すると責務が濁る。

このため `instances.json` を別ファイルとして持つ。

## 受け入れ条件

### AC-01: 公式 Minecraft Launcher の検出

`%APPDATA%\.minecraft` および `launcher_profiles.json` を解析し、Installation ごとのインスタンスを検出できること。Installation に独自の `gameDir` が指定されている場合、そのディレクトリを独立したインスタンスとして検出できること。

### AC-02: Prism Launcher の検出

`%APPDATA%\PrismLauncher\instances` 配下のインスタンスを検出できること。`prismlauncher.cfg` の `InstanceDir` が設定されている場合、そのディレクトリを検索対象にできること。`rootPath` がインスタンスフォルダ配下の `.minecraft`(旧構成では `minecraft`)を指すこと。

### AC-03: CurseForge の検出

`%USERPROFILE%\curseforge\minecraft\Instances` 配下のインスタンスを `minecraftinstance.json` とともに検出できること。CurseForge 設定から Modding Folder を取得できる場合はそれを優先し、取得できない場合は標準パスへフォールバックすること。

### AC-04: ATLauncher の検出

ATLauncher のデータディレクトリ配下 `instances/` のインスタンスを `instance.json` とともに検出できること。

### AC-05: Modrinth App の検出

`%APPDATA%\ModrinthApp\profiles` 配下のプロファイルを検出できること。旧ディレクトリ `%APPDATA%\com.modrinth.theseus` も確認すること。SQLite データベースを読まずに検出が成立すること。

### AC-06: カスタム保存先・Portable 環境

利用者が登録した追加パスが、インスタンス本体としても、ランチャールート(`instances/` `profiles/` `prismlauncher.cfg` を含むディレクトリ)としても解釈され、配下のインスタンスを検出できること。別ドライブに配置された環境が検出できること。

### AC-07: 検索の優先順位

自動検出が「標準パス → ランチャー設定 → 登録済み追加パス」の順で行われ、PC 内の全ドライブ再帰検索が既定では実行されないこと。

### AC-08: インスタンス検証

`mods/` `config/` `resourcepacks/` `saves/` `options.txt` `logs/` のうち 2 つ以上を持つディレクトリをインスタンスと判定し、1 つ以下しか持たない無関係なフォルダを除外できること。ランチャー固有メタデータが読み取れる場合は単独で確定できること。

### AC-09: 重複排除

複数の Detector が同一の正規化済み絶対パスを返した場合、一覧に 1 件だけ表示されること。先に検出された側の `name`・`launcher`・`id` が維持され、`null` または `ModLoader.unknown` のフィールドのみ後続の検出結果で補完されること。`lastPlayed` は新しい方が採用されること。

### AC-10: 同名・別パスの保持

名前が同一でも `rootPath` が異なるインスタンスは、両方とも一覧に表示されること。

### AC-11: Minecraft バージョンの取得

ランチャーメタデータから Minecraft バージョンを取得できること。取得できない場合に `Unknown` として扱われ、検出自体は成功すること。

### AC-12: Mod Loader の取得

Vanilla / Forge / NeoForge / Fabric / Quilt を可能な範囲で判定できること。判定できない場合に `ModLoader.unknown` として扱われ、検出自体は成功すること。

### AC-13: 一覧画面

起動時にインスタンス一覧画面が表示され、ランチャー別の見出しとともにインスタンス名・Minecraft バージョン・Mod Loader・MOD 件数が表示されること。

### AC-14: フィルター・検索

ランチャー別フィルター(すべて / Minecraft / Prism / CurseForge / ATLauncher / Modrinth)とインスタンス名の部分一致検索が動作すること。

### AC-15: 自動解析

インスタンスを選択すると、既存の MOD / クエスト / Patchouli スキャナを用いて翻訳対象が解析され、MOD 件数・翻訳可能 MOD 件数・クエスト形式別の検出状況・ガイドブック一覧・翻訳済み/未翻訳の内訳が表示されること。

### AC-16: 手動追加の永続化

手動追加したパスが `instances.json` へ保存され、アプリ再起動後も一覧に表示されること。インスタンスとしてもランチャールートとしても解釈できないパスは、日本語のエラーメッセージとともに登録されないこと。

保存は原子的書き込みで行い、`save()` を同時に複数回呼び出しても例外にならず最終値が復元できること。書き込み後に一時ファイル・バックアップファイルが残らないこと。

### AC-17: 再検出

`[再検出]` によりアプリを再起動せずに検出をやり直せること。

### AC-18: 詳細検索

自動検出が 0 件の場合にのみ `[PC内を詳しく検索]` が提示されること。詳細検索が深さ上限と除外ディレクトリに従い、キャンセルでき、アクセス権限エラーで中断しないこと。

### AC-19: 最近使用したインスタンス

最後に利用したインスタンスが保存され、次回起動時に一覧上部へ表示されること。保存されたパスが存在しない場合に「見つかりません」と表示され、削除できること。

### AC-20: 設定破損時の安定性

いずれかのランチャー設定ファイルが壊れていても、そのランチャーの検出だけが空になり、他ランチャーの検出とアプリ全体がクラッシュしないこと。

### AC-21: 消滅済みインスタンスの扱い

一覧表示後に `rootPath` が削除されていた場合、選択時に日本語のエラーメッセージが表示され、アプリがクラッシュしないこと。

### AC-22: 既存機能の維持

MOD / クエスト / Patchouli / カスタムファイルの個別翻訳、プロファイルフォルダの手動指定、差分更新、バックアップ、翻訳履歴が従来どおり利用できること。既存のウィジェットテスト(`test/features/shell/main_shell_page_test.dart`)が変更なしで成功すること。

### AC-23: 品質検証

`flutter analyze` と `flutter test` が成功すること。ランチャー設定パーサー、インスタンス検証、重複排除、各 Detector、一覧のフィルター・検索を対象とする自動テストがあること。

## テスト方針

少なくとも次を自動テストで確認する。

**ランチャー設定パーサー(domain、純粋関数)**

- `launcher_profiles.json` の Installation 解析(`gameDir` あり / なし、`lastVersionId` の各形式)
- `prismlauncher.cfg` の `InstanceDir` 解析(未設定 / 絶対パス / 相対パス)
- `instance.cfg` の名前・最終起動日時の解析
- `mmc-pack.json` の `components` から Minecraft バージョンと各 Mod Loader の判定
- `minecraftinstance.json` の名前・`gameVersion`・`baseModLoader` の解析
- `instance.json` の名前・`id`・`loaderVersion` の解析
- 各パーサーが壊れた入力(不正 JSON、必須キー欠落、型不一致)で例外を投げずに空・`null` を返すこと

**インスタンス検証・重複排除(domain、純粋関数)**

- マーカー 2 つ以上でインスタンスと判定すること
- マーカー 1 つ以下では判定しないこと
- 同一の正規化済み絶対パスが 1 件へまとめられること
- 大文字小文字だけが異なるパスが同一と判定されること
- 同名・別パスが両方保持されること
- マージ時に先着側(`base`)の `name`・`launcher`・`id` が維持され、`null`/`ModLoader.unknown` のフィールドのみ後続の検出結果で補完されること

**Detector(infrastructure)**

- `Directory.systemTemp` 配下に各ランチャーのフォルダ構造を再現し、`WindowsEnvironment` を差し替えて検出できること(既存 `test/infrastructure/modtranslation/mod_directory_scanner_test.dart` と同じ手法)
- 標準パスが存在しない場合に空リストを返すこと
- ランチャー設定が壊れている場合に空リストを返し、例外を投げないこと
- Prism の `.minecraft` / `minecraft` / どちらも無い場合の `rootPath` 解決

**一覧・解析(features)**

- ランチャー別フィルターとインスタンス名検索の絞り込み
- 並び順(`lastPlayed` 降順 → 名前昇順、`lastPlayed` なしは末尾)
- インスタンス選択時に `ProfileDirectoryController.setPath()` へ `rootPath` が渡されること
- 自動解析が既存 3 スキャナを呼び、翻訳済み/未翻訳の内訳を `hasExistingTranslation` から集計すること
- 起動時ホーム画面がインスタンス一覧になっていること(`test/widget_test.dart` の更新)

**永続化**

- `instances.json` への手動追加パス・最近使用インスタンスの保存と読み込み
- ファイルが存在しない / 壊れている場合に空状態へフォールバックすること
- 最近使用が最大 5 件で古いものから破棄されること

リリース前に次を順番に実行し、すべて成功させること。

```powershell
flutter pub get
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test
flutter build windows --release
```

## 要検証項目

次の項目は公式資料で確定できていない。実装時に実際のランチャーをインストールした Windows 環境で確認し、相違があれば本仕様と実装の既定値を更新する。本書の基本方針(検索の優先順位、境界としての `MinecraftInstance`、SQLite を読まないこと、安全要件)はその場合も維持する。

- CurseForge の Modding Folder 設定を保持するファイル名およびキー名
- ATLauncher のデータディレクトリ設定の保持場所と、Portable 版の判別方法
- Modrinth App のカスタム App directory 設定を、SQLite を読まずに取得する手段の有無
- Microsoft Store 版 Minecraft Launcher(`launcher_profiles_microsoft_store.json`)の実際の構造と、`.minecraft` 以外の既定ディレクトリの有無
- Prism Launcher Portable 版における `prismlauncher.cfg` の配置と、`InstanceDir` の相対パス解決の基点
- `logs/latest.log` の起動時ログ行の形式(Forge / NeoForge / Fabric / Quilt でそれぞれ確認する)
- 公式ランチャーの `lastVersionId` に現れる NeoForge の ID 形式と、そこから Minecraft バージョンを解決できるかどうか

## 今後の検討事項

- お気に入り登録(一覧上部への固定)は別要件として検討する。
- MultiMC、GDLauncher などの追加ランチャー対応は、本仕様の `LauncherDetector` を実装するだけで追加できる構成とし、対応可否は別要件として検討する。
- 詳細検索の結果を次回以降の検索対象として自動登録するかどうかは、誤検出の蓄積を避けるため本仕様では行わない。必要になれば別要件として検討する。
