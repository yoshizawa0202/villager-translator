import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:villager_translator/domain/modtranslation/jar_contents.dart';
import 'package:villager_translator/domain/modtranslation/lang_codec.dart';
import 'package:villager_translator/domain/modtranslation/mod_scan_entry.dart';
import 'package:villager_translator/domain/modtranslation/mod_scanner.dart';

JarContents _jar(Map<String, String> textEntries) {
  return {
    for (final entry in textEntries.entries)
      entry.key: utf8.encode(entry.value),
  };
}

void main() {
  group('scanModJar', () {
    test('fabric.mod.json と en_us.json を含む MOD が対象一覧に追加される', () {
      final jar = _jar({
        'fabric.mod.json':
            '{"id": "examplemod", "name": "Example", "version": "1.0"}',
        'assets/examplemod/lang/en_us.json': '{"item.example": "Example Item"}',
      });

      final outcome = scanModJar(
        jarRelativePath: 'examplemod.jar',
        jar: jar,
        targetLanguageId: 'ja_jp',
      );

      expect(outcome.skip, isNull);
      expect(outcome.entry, isNotNull);
      expect(outcome.entry!.modInfo.id, 'examplemod');
      expect(outcome.entry!.langFormat, LangFormat.json);
      expect(outcome.entry!.sourceEntries, {'item.example': 'Example Item'});
      expect(outcome.entry!.hasExistingTranslation, isFalse);
    });

    test('MOD 情報を取得できない JAR はスキップされる(受け入れ条件2)', () {
      final jar = _jar({
        'assets/examplemod/lang/en_us.json': '{"item.example": "Example Item"}',
      });

      final outcome = scanModJar(
        jarRelativePath: 'noinfo.jar',
        jar: jar,
        targetLanguageId: 'ja_jp',
      );

      expect(outcome.entry, isNull);
      expect(outcome.skip, isNotNull);
      expect(outcome.skip!.reason, ModScanSkipReason.noModInfo);
    });

    test('en_us lang ファイルを含まない MOD は対象一覧から除外される(受け入れ条件3)', () {
      final jar = _jar({
        'fabric.mod.json':
            '{"id": "nolang", "name": "NoLang", "version": "1.0"}',
      });

      final outcome = scanModJar(
        jarRelativePath: 'nolang.jar',
        jar: jar,
        targetLanguageId: 'ja_jp',
      );

      expect(outcome.entry, isNull);
      expect(outcome.skip!.reason, ModScanSkipReason.noLangFile);
    });

    test('壊れた lang ファイルを含む MOD はスキップされ、理由が記録される(受け入れ条件5)', () {
      final jar = _jar({
        'fabric.mod.json':
            '{"id": "broken", "name": "Broken", "version": "1.0"}',
        'assets/broken/lang/en_us.json': '{not valid json',
      });

      final outcome = scanModJar(
        jarRelativePath: 'broken.jar',
        jar: jar,
        targetLanguageId: 'ja_jp',
      );

      expect(outcome.entry, isNull);
      expect(outcome.skip!.reason, ModScanSkipReason.corruptLangFile);
    });

    test('.lang 形式の en_us ファイルも検出される', () {
      final jar = _jar({
        'fabric.mod.json':
            '{"id": "legacy", "name": "Legacy", "version": "1.0"}',
        'assets/legacy/lang/en_us.lang': 'item.example=Example Item',
      });

      final outcome = scanModJar(
        jarRelativePath: 'legacy.jar',
        jar: jar,
        targetLanguageId: 'ja_jp',
      );

      expect(outcome.entry!.langFormat, LangFormat.lang);
      expect(outcome.entry!.sourceEntries, {'item.example': 'Example Item'});
    });

    test('対象言語の lang ファイルが既に存在する場合は既存バッジになる(受け入れ条件6)', () {
      final jar = _jar({
        'fabric.mod.json':
            '{"id": "existing", "name": "Existing", "version": "1.0"}',
        'assets/existing/lang/en_us.json': '{"item.example": "Example Item"}',
        'assets/existing/lang/ja_jp.json': '{"item.example": "既存翻訳"}',
      });

      final outcome = scanModJar(
        jarRelativePath: 'existing.jar',
        jar: jar,
        targetLanguageId: 'ja_jp',
      );

      expect(outcome.entry!.hasExistingTranslation, isTrue);
    });

    test('対象言語の lang ファイルが存在しない場合は新規バッジになる', () {
      final jar = _jar({
        'fabric.mod.json':
            '{"id": "brandnew", "name": "New", "version": "1.0"}',
        'assets/brandnew/lang/en_us.json': '{"item.example": "Example Item"}',
      });

      final outcome = scanModJar(
        jarRelativePath: 'brandnew.jar',
        jar: jar,
        targetLanguageId: 'ja_jp',
      );

      expect(outcome.entry!.hasExistingTranslation, isFalse);
    });
  });

  group('sortModEntriesById', () {
    test('MOD ID のアルファベット順にソートする(受け入れ条件7)', () {
      final jarZ = _jar({
        'fabric.mod.json': '{"id": "zmod", "name": "Z", "version": "1.0"}',
        'assets/zmod/lang/en_us.json': '{"a": "A"}',
      });
      final jarA = _jar({
        'fabric.mod.json': '{"id": "amod", "name": "A", "version": "1.0"}',
        'assets/amod/lang/en_us.json': '{"a": "A"}',
      });

      final entryZ = scanModJar(
        jarRelativePath: 'z.jar',
        jar: jarZ,
        targetLanguageId: 'ja_jp',
      ).entry!;
      final entryA = scanModJar(
        jarRelativePath: 'a.jar',
        jar: jarA,
        targetLanguageId: 'ja_jp',
      ).entry!;

      final sorted = sortModEntriesById([entryZ, entryA]);

      expect(sorted.map((e) => e.modInfo.id).toList(), ['amod', 'zmod']);
    });
  });
}
