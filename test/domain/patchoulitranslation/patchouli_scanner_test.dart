import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:villager_translator/domain/modtranslation/jar_contents.dart';
import 'package:villager_translator/domain/patchoulitranslation/patchouli_scanner.dart';

JarContents _jar(Map<String, String> textEntries) {
  return {
    for (final entry in textEntries.entries)
      entry.key: utf8.encode(entry.value),
  };
}

void main() {
  group('scanPatchouliBooksInJar', () {
    test('ページ・カテゴリのサブディレクトリを含めて en_us/ 配下を再帰的に検出する(受け入れ条件2)', () {
      final jar = _jar({
        'assets/examplemod/patchouli_books/guide/en_us/book.json':
            '{"name": "Example Guide"}',
        'assets/examplemod/patchouli_books/guide/en_us/categories/intro.json':
            '{"name": "Intro", "description": "Getting started"}',
        'assets/examplemod/patchouli_books/guide/en_us/entries/misc/cool_stuff.json':
            '{"name": "Cool Stuff", "pages": [{"type": "text", "text": "Body"}]}',
      });

      final entries = scanPatchouliBooksInJar(
        jarRelativePath: 'examplemod.jar',
        jar: jar,
        targetLanguageId: 'ja_jp',
      );

      expect(entries, hasLength(1));
      final entry = entries.single;
      expect(entry.modId, 'examplemod');
      expect(entry.bookId, 'guide');
      expect(entry.bookKey, 'examplemod:guide');
      expect(entry.files.map((f) => f.relativePath).toList(), [
        'book.json',
        'categories/intro.json',
        'entries/misc/cool_stuff.json',
      ]);
    });

    test('同一本に属する複数ファイルの抽出結果が1つの翻訳単位に統合される(受け入れ条件4)', () {
      final jar = _jar({
        'assets/examplemod/patchouli_books/guide/en_us/book.json':
            '{"name": "Example Guide"}',
        'assets/examplemod/patchouli_books/guide/en_us/categories/intro.json':
            '{"name": "Intro"}',
      });

      final entries = scanPatchouliBooksInJar(
        jarRelativePath: 'examplemod.jar',
        jar: jar,
        targetLanguageId: 'ja_jp',
      );

      final entry = entries.single;
      expect(entry.sourceEntries, {
        'book.json#0': 'Example Guide',
        'categories/intro.json#0': 'Intro',
      });
    });

    test(
      'name/description/title/text 以外のキー(icon/category 等)は翻訳対象に含まれない(受け入れ条件3)',
      () {
        final jar = _jar({
          'assets/examplemod/patchouli_books/guide/en_us/entries/a.json':
              '{"icon": "minecraft:diamond", "category": "guide:misc", "name": "A"}',
        });

        final entries = scanPatchouliBooksInJar(
          jarRelativePath: 'examplemod.jar',
          jar: jar,
          targetLanguageId: 'ja_jp',
        );

        expect(entries.single.sourceEntries, {'entries/a.json#0': 'A'});
      },
    );

    test('対象言語の全ミラーファイルが揃っている場合のみ既存判定になる(受け入れ条件5)', () {
      final jar = _jar({
        'assets/examplemod/patchouli_books/guide/en_us/book.json':
            '{"name": "Example Guide"}',
        'assets/examplemod/patchouli_books/guide/en_us/entries/a.json':
            '{"name": "A"}',
        'assets/examplemod/patchouli_books/guide/ja_jp/book.json':
            '{"name": "サンプルガイド"}',
        'assets/examplemod/patchouli_books/guide/ja_jp/entries/a.json':
            '{"name": "A訳"}',
      });

      final entries = scanPatchouliBooksInJar(
        jarRelativePath: 'examplemod.jar',
        jar: jar,
        targetLanguageId: 'ja_jp',
      );

      expect(entries.single.hasExistingTranslation, isTrue);
    });

    test('一部のミラーファイルしか存在しない場合は新規/差分更新対象として扱われる(受け入れ条件5)', () {
      final jar = _jar({
        'assets/examplemod/patchouli_books/guide/en_us/book.json':
            '{"name": "Example Guide"}',
        'assets/examplemod/patchouli_books/guide/en_us/entries/a.json':
            '{"name": "A"}',
        // entries/a.json のミラーが欠けている。
        'assets/examplemod/patchouli_books/guide/ja_jp/book.json':
            '{"name": "サンプルガイド"}',
      });

      final entries = scanPatchouliBooksInJar(
        jarRelativePath: 'examplemod.jar',
        jar: jar,
        targetLanguageId: 'ja_jp',
      );

      expect(entries.single.hasExistingTranslation, isFalse);
    });

    test('ミラーファイルが1件も存在しない場合は新規判定になる', () {
      final jar = _jar({
        'assets/examplemod/patchouli_books/guide/en_us/book.json':
            '{"name": "Example Guide"}',
      });

      final entries = scanPatchouliBooksInJar(
        jarRelativePath: 'examplemod.jar',
        jar: jar,
        targetLanguageId: 'ja_jp',
      );

      expect(entries.single.hasExistingTranslation, isFalse);
    });

    test('1つの JAR に複数の本が含まれる場合、それぞれ個別に検出される', () {
      final jar = _jar({
        'assets/modx/patchouli_books/guidea/en_us/book.json':
            '{"name": "A Guide"}',
        'assets/modx/patchouli_books/guideb/en_us/book.json':
            '{"name": "B Guide"}',
      });

      final entries = scanPatchouliBooksInJar(
        jarRelativePath: 'modx.jar',
        jar: jar,
        targetLanguageId: 'ja_jp',
      );

      expect(
        entries.map((e) => e.bookKey).toList(),
        // sortPatchouliBookEntries によりアルファベット順。
        ['modx:guidea', 'modx:guideb'],
      );
    });

    test('Patchouli ガイドブックを含まない JAR は空リストを返す', () {
      final jar = _jar({'assets/examplemod/lang/en_us.json': '{"a": "A"}'});

      final entries = scanPatchouliBooksInJar(
        jarRelativePath: 'examplemod.jar',
        jar: jar,
        targetLanguageId: 'ja_jp',
      );

      expect(entries, isEmpty);
    });
  });
}
