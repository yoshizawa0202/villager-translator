import '../modtranslation/jar_contents.dart';
import 'patchouli_book_entry.dart';
import 'patchouli_string_extractor.dart';

final _enUsBookFilePattern = RegExp(
  r'^assets/([^/]+)/patchouli_books/([^/]+)/en_us/(.+\.json)$',
  caseSensitive: false,
);

/// [jar](1つの JAR の展開済み内容)から Patchouli ガイドブックを検出する
/// (feature-spec.md §8.1)。
///
/// 実ファイル I/O を伴わない純粋関数とし、infrastructure 層が展開した
/// [JarContents] を受け取る形にすることでテスト容易性を確保する
/// (`mod_scanner.dart` と同じ設計方針)。1つの JAR に複数の本、または本が
/// 存在しない場合もあるため、`ModScanOutcome` のような found/skip の二択
/// ではなく一覧を返す(JAR 自体が開けない失敗は infrastructure 層で検出する)。
List<PatchouliBookEntry> scanPatchouliBooksInJar({
  required String jarRelativePath,
  required JarContents jar,
  required String targetLanguageId,
}) {
  final matchingPaths =
      jar.keys.where((path) => _enUsBookFilePattern.hasMatch(path)).toList()
        ..sort();

  // 本(modId:bookId)ごとに、en_us/ からの相対パス → JAR 内の実パスを集約する。
  final groupOrder = <String>[];
  final groupModId = <String, String>{};
  final groupBookId = <String, String>{};
  final groupFiles = <String, Map<String, String>>{};

  for (final jarPath in matchingPaths) {
    final match = _enUsBookFilePattern.firstMatch(jarPath)!;
    final modId = match.group(1)!;
    final bookId = match.group(2)!;
    final fileRelativePath = match.group(3)!;

    final groupKey = '${modId.toLowerCase()}:${bookId.toLowerCase()}';
    if (!groupFiles.containsKey(groupKey)) {
      groupOrder.add(groupKey);
      groupModId[groupKey] = modId;
      groupBookId[groupKey] = bookId;
      groupFiles[groupKey] = {};
    }
    groupFiles[groupKey]![fileRelativePath] = jarPath;
  }

  final entries = <PatchouliBookEntry>[];

  for (final groupKey in groupOrder) {
    final modId = groupModId[groupKey]!;
    final bookId = groupBookId[groupKey]!;
    final filePaths = groupFiles[groupKey]!;
    final sortedRelativePaths = filePaths.keys.toList()..sort();

    final files = <PatchouliBookFile>[];
    final sourceEntries = <String, String>{};
    var hasExistingTranslation = true;

    for (final relativePath in sortedRelativePaths) {
      final content = readJarText(jar, filePaths[relativePath]!) ?? '';
      final unit = buildPatchouliFileTranslationUnit(content);

      files.add(
        PatchouliBookFile(
          relativePath: relativePath,
          originalContent: content,
          spans: unit.spans,
        ),
      );
      for (final entry in unit.entries.entries) {
        sourceEntries['$relativePath#${entry.key}'] = entry.value;
      }

      if (!_hasMirrorFile(jar, modId, bookId, targetLanguageId, relativePath)) {
        hasExistingTranslation = false;
      }
    }

    entries.add(
      PatchouliBookEntry(
        modId: modId,
        bookId: bookId,
        jarRelativePath: jarRelativePath,
        files: files,
        sourceEntries: sourceEntries,
        hasExistingTranslation: hasExistingTranslation,
      ),
    );
  }

  return sortPatchouliBookEntries(entries);
}

/// [targetLanguageId] 配下の、[relativePath] に対応するミラーファイルが JAR
/// 内に存在するかどうかを判定する(ディレクトリミラー方式、feature-spec.md §8.1)。
bool _hasMirrorFile(
  JarContents jar,
  String modId,
  String bookId,
  String targetLanguageId,
  String relativePath,
) {
  final mirrorPath =
      'assets/$modId/patchouli_books/$bookId/$targetLanguageId/$relativePath';
  return jar.keys.any((k) => k.toLowerCase() == mirrorPath.toLowerCase());
}

/// 本を `{modId}:{bookId}` のアルファベット順にソートする(決定論的な処理順)。
List<PatchouliBookEntry> sortPatchouliBookEntries(
  Iterable<PatchouliBookEntry> entries,
) {
  final sorted = entries.toList()
    ..sort((a, b) => a.bookKey.compareTo(b.bookKey));
  return sorted;
}
