import 'package:flutter_test/flutter_test.dart';
import 'package:villager_translator/domain/patchoulitranslation/patchouli_book_entry.dart';
import 'package:villager_translator/domain/patchoulitranslation/patchouli_output_builder.dart';
import 'package:villager_translator/domain/patchoulitranslation/patchouli_string_extractor.dart';
import 'package:villager_translator/domain/patchoulitranslation/patchouli_translation_service.dart';

PatchouliBookFile _file(String relativePath, String content) {
  final unit = buildPatchouliFileTranslationUnit(content);
  return PatchouliBookFile(
    relativePath: relativePath,
    originalContent: content,
    spans: unit.spans,
  );
}

void main() {
  group('buildPatchouliJarOutputEntries', () {
    test('en_us/ と同じ相対パスで {lang}/ 配下にミラーされた JAR パスを組み立てる(受け入れ条件1)', () {
      const content = '{"name": "Example Guide"}';
      final file = _file('book.json', content);
      final entry = PatchouliBookEntry(
        modId: 'examplemod',
        bookId: 'guide',
        jarRelativePath: 'examplemod.jar',
        files: [file],
        sourceEntries: {'book.json#0': 'Example Guide'},
        hasExistingTranslation: false,
      );
      final output = PatchouliTranslationOutput(
        entry: entry,
        entries: {'book.json#0': 'サンプルガイド'},
      );

      final results = buildPatchouliJarOutputEntries(output, 'ja_jp');

      expect(results, hasLength(1));
      expect(
        results.single.jarPath,
        'assets/examplemod/patchouli_books/guide/ja_jp/book.json',
      );
      expect(results.single.content, '{"name": "サンプルガイド"}');
    });

    test('サブディレクトリを含む相対パスも維持される', () {
      const content = '{"name": "Cool Stuff"}';
      final file = _file('entries/misc/cool_stuff.json', content);
      final entry = PatchouliBookEntry(
        modId: 'examplemod',
        bookId: 'guide',
        jarRelativePath: 'examplemod.jar',
        files: [file],
        sourceEntries: {'entries/misc/cool_stuff.json#0': 'Cool Stuff'},
        hasExistingTranslation: false,
      );
      final output = PatchouliTranslationOutput(
        entry: entry,
        entries: {'entries/misc/cool_stuff.json#0': 'クールな物'},
      );

      final results = buildPatchouliJarOutputEntries(output, 'ja_jp');

      expect(
        results.single.jarPath,
        'assets/examplemod/patchouli_books/guide/ja_jp/entries/misc/cool_stuff.json',
      );
    });

    test('フルコピー方式: icon/category 等の翻訳対象外キーは変更されず、対象キーのみ置き換わる(受け入れ条件7)', () {
      const content =
          '{"icon": "minecraft:diamond", "name": "Cool Stuff", '
          '"category": "guide:misc"}';
      final file = _file('entries/a.json', content);
      final entry = PatchouliBookEntry(
        modId: 'examplemod',
        bookId: 'guide',
        jarRelativePath: 'examplemod.jar',
        files: [file],
        sourceEntries: {'entries/a.json#0': 'Cool Stuff'},
        hasExistingTranslation: false,
      );
      final output = PatchouliTranslationOutput(
        entry: entry,
        entries: {'entries/a.json#0': 'クールな物'},
      );

      final results = buildPatchouliJarOutputEntries(output, 'ja_jp');

      expect(
        results.single.content,
        '{"icon": "minecraft:diamond", "name": "クールな物", '
        '"category": "guide:misc"}',
      );
    });

    test('複数ファイルの本は、ファイルごとに正しい複合キーの内容のみが適用される', () {
      const bookContent = '{"name": "Example Guide"}';
      const entryContent = '{"name": "A", "text": "Body A"}';
      final bookFile = _file('book.json', bookContent);
      final entryFile = _file('entries/a.json', entryContent);

      final entry = PatchouliBookEntry(
        modId: 'examplemod',
        bookId: 'guide',
        jarRelativePath: 'examplemod.jar',
        files: [bookFile, entryFile],
        sourceEntries: {
          'book.json#0': 'Example Guide',
          'entries/a.json#0': 'A',
          'entries/a.json#1': 'Body A',
        },
        hasExistingTranslation: false,
      );
      final output = PatchouliTranslationOutput(
        entry: entry,
        entries: {
          'book.json#0': 'サンプルガイド',
          'entries/a.json#0': 'A訳',
          'entries/a.json#1': '本文A',
        },
      );

      final results = buildPatchouliJarOutputEntries(output, 'ja_jp');

      final byPath = {for (final r in results) r.jarPath: r.content};
      expect(
        byPath['assets/examplemod/patchouli_books/guide/ja_jp/book.json'],
        '{"name": "サンプルガイド"}',
      );
      expect(
        byPath['assets/examplemod/patchouli_books/guide/ja_jp/entries/a.json'],
        '{"name": "A訳", "text": "本文A"}',
      );
    });

    test('翻訳結果に含まれないエントリは元の内容のまま出力される(部分成功)', () {
      const content = '{"name": "A", "title": "T"}';
      final file = _file('entries/a.json', content);
      final entry = PatchouliBookEntry(
        modId: 'examplemod',
        bookId: 'guide',
        jarRelativePath: 'examplemod.jar',
        files: [file],
        sourceEntries: {'entries/a.json#0': 'A', 'entries/a.json#1': 'T'},
        hasExistingTranslation: false,
      );
      final output = PatchouliTranslationOutput(
        entry: entry,
        entries: {'entries/a.json#0': 'A訳'},
      );

      final results = buildPatchouliJarOutputEntries(output, 'ja_jp');

      expect(results.single.content, '{"name": "A訳", "title": "T"}');
    });
  });
}
