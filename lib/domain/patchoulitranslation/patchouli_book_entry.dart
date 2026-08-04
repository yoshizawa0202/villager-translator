import 'patchouli_string_extractor.dart';

/// Patchouli ガイドブック内の1ファイル(`en_us/` 配下)分の情報
/// (feature-spec.md §8.1)。
class PatchouliBookFile {
  const PatchouliBookFile({
    required this.relativePath,
    required this.originalContent,
    required this.spans,
  });

  /// `en_us/` からの相対パス(`/` 区切り、例 `entries/misc/cool_stuff.json`)。
  final String relativePath;

  /// ファイルの原文全体(フルコピー方式の再構成の基点、feature-spec.md §8.2)。
  final String originalContent;

  /// [originalContent] から抽出した翻訳対象文字列のスパン一覧(抽出順)。
  final List<PatchouliStringSpan> spans;
}

/// スキャン対象一覧に含まれる Patchouli ガイドブック1冊分の情報
/// (feature-spec.md §8.1)。
class PatchouliBookEntry {
  const PatchouliBookEntry({
    required this.modId,
    required this.bookId,
    required this.jarRelativePath,
    required this.files,
    required this.sourceEntries,
    required this.hasExistingTranslation,
  });

  final String modId;
  final String bookId;

  /// `mods/` からの相対パス(テーブル表示列)。
  final String jarRelativePath;

  /// この本に属する `en_us/` 配下の全ファイル(相対パス順)。
  final List<PatchouliBookFile> files;

  /// 全ファイルの抽出結果を1つの翻訳単位に統合したもの(feature-spec.md §8.1、
  /// 受け入れ条件4)。キーは `{ファイル相対パス}#{ファイル内の抽出順連番}` の
  /// 複合キー(feature-spec.md §8.1 受け入れ条件6 の「ファイル相対パス+キー位置」)。
  final Map<String, String> sourceEntries;

  /// 対象言語の `{lang}/` ミラーファイルが、`en_us/` の全ファイル分 JAR 内に
  /// 存在するか(受け入れ条件5)。一部または全部が欠けている場合は `false`。
  final bool hasExistingTranslation;

  /// `{modId}:{bookId}` 形式の表示・ソートキー。
  String get bookKey => '$modId:$bookId';
}

/// スキャン時に JAR がスキップされた理由。
enum PatchouliScanSkipReason {
  /// JAR 自体が破損していて開けない(infrastructure 層で検出)。
  corruptJar,
}

/// スキップされた JAR 1件分の記録(ログ出力用)。
class PatchouliScanSkip {
  const PatchouliScanSkip({
    required this.jarRelativePath,
    required this.reason,
    this.detail,
  });

  final String jarRelativePath;
  final PatchouliScanSkipReason reason;

  /// ログに残す補足情報(例外メッセージ等)。
  final String? detail;
}

/// スキャン結果全体(対象一覧 + スキップ記録)。
class PatchouliScanResult {
  const PatchouliScanResult({required this.entries, required this.skips});

  final List<PatchouliBookEntry> entries;
  final List<PatchouliScanSkip> skips;
}
