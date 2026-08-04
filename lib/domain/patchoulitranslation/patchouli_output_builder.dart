import 'patchouli_string_extractor.dart';
import 'patchouli_translation_service.dart';

/// JAR へ書き込む1エントリ(JAR 内パス `/` 区切り → 内容)。
class PatchouliJarOutputEntry {
  const PatchouliJarOutputEntry({required this.jarPath, required this.content});

  final String jarPath;
  final String content;
}

/// [output] から、JAR へ書き込む `{lang}/` ミラーファイル一式を組み立てる
/// (feature-spec.md §8.2)。
///
/// 出力ファイルは `en_us/` と同じディレクトリ構造を
/// `assets/{modId}/patchouli_books/{bookId}/{lang}/` 配下にミラーする
/// (`docs/specs/006-patchouli-translation.md` の「Patchouli 出力構造の
/// 検証結果」、受け入れ条件1)。各ファイルは対応する en_us ファイルの完全な
/// コピーを基に、抽出した `name`/`description`/`title`/`text` の値のみを
/// 翻訳結果で置き換えた内容とする(フルコピー方式、受け入れ条件7)。
List<PatchouliJarOutputEntry> buildPatchouliJarOutputEntries(
  PatchouliTranslationOutput output,
  String targetLanguageId,
) {
  final entry = output.entry;
  final results = <PatchouliJarOutputEntry>[];

  for (final file in entry.files) {
    final prefix = '${file.relativePath}#';
    final localEntries = <String, String>{
      for (final e in output.entries.entries)
        if (e.key.startsWith(prefix)) e.key.substring(prefix.length): e.value,
    };

    final content = reconstructPatchouliFile(
      file.originalContent,
      file.spans,
      localEntries,
    );

    final jarPath =
        'assets/${entry.modId}/patchouli_books/${entry.bookId}/'
        '$targetLanguageId/${file.relativePath}';
    results.add(PatchouliJarOutputEntry(jarPath: jarPath, content: content));
  }

  return results;
}
