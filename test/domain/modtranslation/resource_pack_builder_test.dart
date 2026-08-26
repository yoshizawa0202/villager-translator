import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:villager_translator/domain/modtranslation/mod_translation_service.dart';
import 'package:villager_translator/domain/modtranslation/resource_pack_builder.dart';
import 'package:villager_translator/domain/translation/lang_codec.dart';

void main() {
  group('buildPackMcmeta', () {
    test('pack_format 9 の pack.mcmeta を生成する', () {
      final mcmeta = jsonDecode(buildPackMcmeta());
      expect(mcmeta['pack']['pack_format'], 9);
    });
  });

  group('buildResourcePackFiles', () {
    test('複数 MOD を単一のリソースパックにまとめる(受け入れ条件12)', () {
      final files = buildResourcePackFiles(
        outputs: [
          ModTranslationOutput(
            jarRelativePath: 'moda.jar',
            modId: 'moda',
            format: LangFormat.json,
            entries: {'b': '2', 'a': '1'},
          ),
          ModTranslationOutput(
            jarRelativePath: 'modb.jar',
            modId: 'modb',
            format: LangFormat.lang,
            entries: {'y': '2', 'x': '1'},
          ),
        ],
        targetLanguageId: 'ja_jp',
      );

      expect(files.containsKey('pack.mcmeta'), isTrue);
      expect(files.containsKey('assets/moda/lang/ja_jp.json'), isTrue);
      expect(files.containsKey('assets/modb/lang/ja_jp.lang'), isTrue);
    });

    test('lang ファイルのキーがソートされて出力される(受け入れ条件13)', () {
      final files = buildResourcePackFiles(
        outputs: [
          ModTranslationOutput(
            jarRelativePath: 'moda.jar',
            modId: 'moda',
            format: LangFormat.json,
            entries: {'b': '2', 'a': '1'},
          ),
        ],
        targetLanguageId: 'ja_jp',
      );

      final json = files['assets/moda/lang/ja_jp.json']!;
      expect(json.indexOf('"a"'), lessThan(json.indexOf('"b"')));
    });

    test('.lang 形式もキーがソートされて出力される', () {
      final files = buildResourcePackFiles(
        outputs: [
          ModTranslationOutput(
            jarRelativePath: 'modb.jar',
            modId: 'modb',
            format: LangFormat.lang,
            entries: {'y': '2', 'x': '1'},
          ),
        ],
        targetLanguageId: 'ja_jp',
      );

      expect(files['assets/modb/lang/ja_jp.lang'], 'x=1\ny=2');
    });

    test('同じ出力先になる複数JARを無言で上書きしない(受け入れ条件17)', () {
      expect(
        () => buildResourcePackFiles(
          outputs: [
            ModTranslationOutput(
              jarRelativePath: 'same-1.jar',
              modId: 'same',
              format: LangFormat.json,
              entries: const {'a': '1'},
            ),
            ModTranslationOutput(
              jarRelativePath: 'same-2.jar',
              modId: 'same',
              format: LangFormat.json,
              entries: const {'b': '2'},
            ),
          ],
          targetLanguageId: 'ja_jp',
        ),
        throwsA(isA<DuplicateModOutputPathException>()),
      );
    });
  });
}
