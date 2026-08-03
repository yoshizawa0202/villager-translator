import 'lang_codec.dart';
import 'mod_info.dart';

/// スキャン対象一覧に含まれる MOD 1件分の情報(feature-spec.md §6.1)。
class ModScanEntry {
  const ModScanEntry({
    required this.modInfo,
    required this.jarRelativePath,
    required this.langFormat,
    required this.sourceLangPath,
    required this.sourceEntries,
    required this.hasExistingTranslation,
  });

  final ModInfo modInfo;

  /// `mods/` からの相対パス(テーブル表示列)。
  final String jarRelativePath;

  final LangFormat langFormat;

  /// JAR 内での `en_us` lang ファイルのパス(例: `assets/examplemod/lang/en_us.json`)。
  final String sourceLangPath;

  /// `en_us` の内容(翻訳元)。
  final Map<String, String> sourceEntries;

  /// 対象言語の lang ファイルが JAR 内に既に存在するか(表示用バッジ)。
  final bool hasExistingTranslation;
}

/// スキャン時に MOD がスキップされた理由(feature-spec.md §6.1)。
enum ModScanSkipReason {
  /// `fabric.mod.json` `mods.toml` `MANIFEST.MF` のいずれからも MOD 情報を
  /// 取得できなかった。
  noModInfo,

  /// `lang/en_us.json` `lang/en_us.lang` のいずれも存在しない。
  noLangFile,

  /// lang ファイルが存在するが破損していてパースできない。
  corruptLangFile,

  /// JAR 自体が破損していて開けない(infrastructure 層で検出)。
  corruptJar,
}

/// スキップされた MOD 1件分の記録(ログ出力用)。
class ModScanSkip {
  const ModScanSkip({
    required this.jarRelativePath,
    required this.reason,
    this.detail,
  });

  final String jarRelativePath;
  final ModScanSkipReason reason;

  /// ログに残す補足情報(例外メッセージ等)。
  final String? detail;
}

/// スキャン結果全体(対象一覧 + スキップ記録)。
class ModScanResult {
  const ModScanResult({required this.entries, required this.skips});

  final List<ModScanEntry> entries;
  final List<ModScanSkip> skips;
}
