import 'package:flutter_test/flutter_test.dart';
import 'package:villager_translator/domain/patchoulitranslation/patchouli_string_extractor.dart';

void main() {
  group('extractPatchouliTranslatableSpans', () {
    test('name/description/title/text の単一文字列値を抽出する', () {
      const content = '''
{
  "name": "Cool Stuff",
  "icon": "minecraft:diamond",
  "category": "patchouli:misc/cool_stuff",
  "pages": [
    {
      "type": "text",
      "title": "Chapter One",
      "text": "Some body text."
    }
  ]
}
''';
      final spans = extractPatchouliTranslatableSpans(content);

      expect(spans.map((s) => s.rawValue).toList(), [
        'Cool Stuff',
        'Chapter One',
        'Some body text.',
      ]);
    });

    test('icon/category/pages(type) 等の対象外キーは抽出しない(受け入れ条件3)', () {
      const content = '''
{
  "icon": "minecraft:diamond",
  "category": "patchouli:misc/cool_stuff",
  "pages": [{"type": "text"}]
}
''';
      expect(extractPatchouliTranslatableSpans(content), isEmpty);
    });

    test('値が文字列でない name/text は抽出しない', () {
      const content = '{"name": 123, "text": null, "title": true}';
      expect(extractPatchouliTranslatableSpans(content), isEmpty);
    });

    test('エスケープされた " を含む値を正しく抽出する', () {
      const content = r'"text": "Say \"Hello\" to the world"';
      final spans = extractPatchouliTranslatableSpans(content);

      expect(spans, hasLength(1));
      expect(spans.single.rawValue, r'Say \"Hello\" to the world');
    });

    test('キーが引用符で囲まれていない箇所は誤検出しない', () {
      const content = 'this text mentions title and name but is not JSON';
      expect(extractPatchouliTranslatableSpans(content), isEmpty);
    });

    test('name/description/title/text を含まない JSON は空リストを返す', () {
      const content = '{"icon": "minecraft:diamond"}';
      expect(extractPatchouliTranslatableSpans(content), isEmpty);
    });
  });

  group('decodePatchouliJsonEscapes / encodePatchouliJsonEscapes', () {
    test(r'\" \\ \n をデコードし、再エンコードで往復する', () {
      const raw = r'Say \"Hello\"\nand a backslash \\ here';
      final decoded = decodePatchouliJsonEscapes(raw);

      expect(decoded, 'Say "Hello"\nand a backslash \\ here');
      expect(encodePatchouliJsonEscapes(decoded), raw);
    });

    test('日本語はエスケープされずそのまま往復する', () {
      const value = 'こんにちは、世界';
      final encoded = encodePatchouliJsonEscapes(value);

      expect(encoded, value);
      expect(decodePatchouliJsonEscapes(encoded), value);
    });
  });

  group('buildPatchouliFileTranslationUnit / reconstructPatchouliFile', () {
    test('抽出順の連番キーでエントリを構築する', () {
      const content = '{"name": "N", "title": "T"}';
      final unit = buildPatchouliFileTranslationUnit(content);

      expect(unit.entries, {'0': 'N', '1': 'T'});
    });

    test('翻訳結果で name/title のみ置き換え、icon 等の構造は変更しない(フルコピー方式、受け入れ条件7)', () {
      const content =
          '{"icon": "minecraft:diamond", "name": "Cool Stuff", '
          '"category": "patchouli:misc/cool_stuff"}';
      final unit = buildPatchouliFileTranslationUnit(content);

      final reconstructed = reconstructPatchouliFile(
        unit.originalContent,
        unit.spans,
        {'0': 'クールな物'},
      );

      expect(
        reconstructed,
        '{"icon": "minecraft:diamond", "name": "クールな物", '
        '"category": "patchouli:misc/cool_stuff"}',
      );
    });

    test('翻訳結果が欠けているスパンは元の内容のまま残る(部分成功)', () {
      const content = '{"name": "N", "title": "T"}';
      final unit = buildPatchouliFileTranslationUnit(content);

      final reconstructed = reconstructPatchouliFile(
        unit.originalContent,
        unit.spans,
        {'0': '名前'},
      );

      expect(reconstructed, '{"name": "名前", "title": "T"}');
    });

    test('置換後の値に含まれる " や \\ は再エスケープされる', () {
      const content = '{"text": "Hello"}';
      final unit = buildPatchouliFileTranslationUnit(content);

      final reconstructed = reconstructPatchouliFile(
        unit.originalContent,
        unit.spans,
        {'0': r'He said "hi" and used \'},
      );

      expect(reconstructed, r'{"text": "He said \"hi\" and used \\"}');
    });
  });
}
