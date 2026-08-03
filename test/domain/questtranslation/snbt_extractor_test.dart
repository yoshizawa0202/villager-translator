import 'package:flutter_test/flutter_test.dart';
import 'package:villager_translator/domain/questtranslation/snbt_extractor.dart';

void main() {
  group('extractSnbtTranslatableSpans', () {
    test('title/subtitle/description の単一文字列値を抽出する', () {
      const content = '''
{
	title: "Chapter One"
	subtitle: "The Beginning"
	quests: [
		{
			description: "A simple quest"
		}
	]
}
''';
      final spans = extractSnbtTranslatableSpans(content);

      expect(spans.map((s) => s.rawValue).toList(), [
        'Chapter One',
        'The Beginning',
        'A simple quest',
      ]);
    });

    test('description の配列(複数行)内のすべての文字列を抽出する', () {
      const content = '''
description: [
	"Line one"
	"Line two"
]
''';
      final spans = extractSnbtTranslatableSpans(content);
      expect(spans.map((s) => s.rawValue).toList(), ['Line one', 'Line two']);
    });

    test('エスケープされた " を含む値を正しく抽出する(受け入れ条件4)', () {
      const content = r'title: "Say \"Hello\" to the world"';
      final spans = extractSnbtTranslatableSpans(content);

      expect(spans, hasLength(1));
      expect(spans.single.rawValue, r'Say \"Hello\" to the world');
    });

    test('キーに似た他の単語(例: subtitled)は誤検出しない', () {
      const content = 'subtitled: "not a match"';
      final spans = extractSnbtTranslatableSpans(content);
      expect(spans, isEmpty);
    });

    test('title/subtitle/description を含まない SNBT は空リストを返す', () {
      const content = '{ id: "ABCDEF" x: 0.0d y: 0.0d }';
      expect(extractSnbtTranslatableSpans(content), isEmpty);
    });
  });

  group('decodeSnbtEscapes / encodeSnbtEscapes', () {
    test('\\" と \\\\ をデコードし、再エンコードで往復する', () {
      const raw = r'Say \"Hello\" and a backslash \\ here';
      final decoded = decodeSnbtEscapes(raw);

      expect(decoded, 'Say "Hello" and a backslash \\ here');
      expect(encodeSnbtEscapes(decoded), raw);
    });
  });

  group('buildSnbtTranslationUnit / reconstructSnbt', () {
    test('抽出順の連番キーでエントリを構築する', () {
      const content = 'title: "T"\nsubtitle: "S"';
      final unit = buildSnbtTranslationUnit(content);

      expect(unit.entries, {'0': 'T', '1': 'S'});
    });

    test('翻訳結果で同一ファイルを上書き再構成する(受け入れ条件5)', () {
      const content = 'title: "Hello"\nother: "unchanged"\nsubtitle: "World"';
      final unit = buildSnbtTranslationUnit(content);

      final reconstructed = reconstructSnbt(unit.originalContent, unit.spans, {
        '0': 'こんにちは',
        '1': '世界',
      });

      expect(
        reconstructed,
        'title: "こんにちは"\nother: "unchanged"\nsubtitle: "世界"',
      );
    });

    test('翻訳結果が欠けているスパンは元の内容のまま残る(部分成功)', () {
      const content = 'title: "Hello"\nsubtitle: "World"';
      final unit = buildSnbtTranslationUnit(content);

      final reconstructed = reconstructSnbt(unit.originalContent, unit.spans, {
        '0': 'こんにちは',
      });

      expect(reconstructed, 'title: "こんにちは"\nsubtitle: "World"');
    });

    test('置換後の値に含まれる " や \\ は再エスケープされる', () {
      const content = 'title: "Hello"';
      final unit = buildSnbtTranslationUnit(content);

      final reconstructed = reconstructSnbt(unit.originalContent, unit.spans, {
        '0': r'He said "hi" and used \',
      });

      expect(reconstructed, r'title: "He said \"hi\" and used \\"');
    });
  });
}
