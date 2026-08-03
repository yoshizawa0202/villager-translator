import 'jar_contents.dart';
import 'lang_codec.dart';
import 'mod_info_extractor.dart';
import 'mod_scan_entry.dart';

/// 1つの JAR をスキャンした結果(対象一覧への追加、またはスキップ)。
class ModScanOutcome {
  const ModScanOutcome.found(ModScanEntry entry) : entry = entry, skip = null;

  const ModScanOutcome.skipped(ModScanSkip skip) : entry = null, skip = skip;

  final ModScanEntry? entry;
  final ModScanSkip? skip;
}

final _enUsLangPattern = RegExp(
  r'(^|/)lang/en_us\.(json|lang)$',
  caseSensitive: false,
);

/// [jar](1つの JAR の展開済み内容)をスキャンし、対象一覧への追加可否を判定する
/// (feature-spec.md §6.1)。
///
/// 実ファイル I/O を伴わない純粋関数とし、infrastructure 層が展開した
/// [JarContents] を受け取る形にすることでテスト容易性を確保する。
ModScanOutcome scanModJar({
  required String jarRelativePath,
  required JarContents jar,
  required String targetLanguageId,
}) {
  final modInfo = resolveModInfo(
    fabricModJson: readJarText(jar, 'fabric.mod.json'),
    modsToml: readJarText(jar, 'META-INF/mods.toml'),
    manifestMf: readJarText(jar, 'META-INF/MANIFEST.MF'),
  );

  if (modInfo == null) {
    return ModScanOutcome.skipped(
      ModScanSkip(
        jarRelativePath: jarRelativePath,
        reason: ModScanSkipReason.noModInfo,
      ),
    );
  }

  final langPath = _findEnUsLangPath(jar, modInfo.id);
  if (langPath == null) {
    return ModScanOutcome.skipped(
      ModScanSkip(
        jarRelativePath: jarRelativePath,
        reason: ModScanSkipReason.noLangFile,
      ),
    );
  }

  final format = langPath.toLowerCase().endsWith('.json')
      ? LangFormat.json
      : LangFormat.lang;

  Map<String, String> sourceEntries;
  try {
    sourceEntries = decodeLang(readJarText(jar, langPath)!, format);
  } on FormatException catch (e) {
    return ModScanOutcome.skipped(
      ModScanSkip(
        jarRelativePath: jarRelativePath,
        reason: ModScanSkipReason.corruptLangFile,
        detail: e.message,
      ),
    );
  }

  return ModScanOutcome.found(
    ModScanEntry(
      modInfo: modInfo,
      jarRelativePath: jarRelativePath,
      langFormat: format,
      sourceLangPath: langPath,
      sourceEntries: sourceEntries,
      hasExistingTranslation: hasExistingTranslationInJar(
        jar,
        modInfo.id,
        targetLanguageId,
      ),
    ),
  );
}

/// JAR 内から `*/lang/en_us.json` または `*/lang/en_us.lang` を探す。
///
/// `assets/{modId}/lang/` 配下のものを優先し、見つからなければ一致した
/// パスのうち辞書順で最初のものを使う(複数 MOD が同梱された特殊な JAR 向けの
/// フォールバック)。
String? _findEnUsLangPath(JarContents jar, String modId) {
  final matches =
      jar.keys.where((path) => _enUsLangPattern.hasMatch(path)).toList()
        ..sort();
  if (matches.isEmpty) return null;

  final preferredPrefix = 'assets/$modId/lang/';
  return matches.firstWhere(
    (path) => path.toLowerCase().startsWith(preferredPrefix.toLowerCase()),
    orElse: () => matches.first,
  );
}

/// 対象言語の `assets/{modId}/lang/{targetLanguageId}.json|.lang` が JAR 内に
/// 既に存在するかどうかを判定する(既存/新規バッジ表示用、feature-spec.md §6.1)。
bool hasExistingTranslationInJar(
  JarContents jar,
  String modId,
  String targetLanguageId,
) {
  final jsonPath = 'assets/$modId/lang/$targetLanguageId.json';
  final langPath = 'assets/$modId/lang/$targetLanguageId.lang';
  return jar.keys.any(
    (path) =>
        path.toLowerCase() == jsonPath.toLowerCase() ||
        path.toLowerCase() == langPath.toLowerCase(),
  );
}

/// 選択した MOD を MOD ID のアルファベット順にソートする
/// (決定論的な処理順、feature-spec.md §6.2、受け入れ条件7)。
List<ModScanEntry> sortModEntriesById(Iterable<ModScanEntry> entries) {
  final sorted = entries.toList()
    ..sort((a, b) => a.modInfo.id.compareTo(b.modInfo.id));
  return sorted;
}
