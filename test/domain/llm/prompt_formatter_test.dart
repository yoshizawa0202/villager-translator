import 'package:flutter_test/flutter_test.dart';
import 'package:villager_translator/domain/llm/prompt_formatter.dart';
import 'package:villager_translator/domain/llm/translation_wire_codec.dart';

void main() {
  group('formatUserPrompt', () {
    test('{language} {line_count} {content} を正しく置換する', () {
      final result = formatUserPrompt(
        'Translate into {language}.\nLines: {line_count}\n{content}',
        content: {'a': 'Hello', 'b': 'World'},
        targetLanguage: '日本語',
      );

      expect(
        result,
        startsWith('Translate into 日本語.\nLines: 2\na: "Hello"\nb: "World"'),
      );
      expect(result, endsWith(kTranslationWireProtocolInstruction));
    });

    test('本文中にたまたま含まれる波括弧を誤って置換しない', () {
      final result = formatUserPrompt(
        '{content}',
        content: {'a': 'literal {language} text'},
        targetLanguage: 'French',
      );

      expect(result, startsWith('a: "literal {language} text"'));
    });

    test('content のエントリ順(挿入順)を維持する', () {
      final result = formatUserPrompt(
        '{content}',
        content: {'z': '1', 'a': '2', 'm': '3'},
        targetLanguage: 'en',
      );

      expect(result, startsWith('z: "1"\na: "2"\nm: "3"'));
    });

    test('値中の改行をエントリ境界へ変換せずJSON文字列として符号化する', () {
      final result = formatUserPrompt(
        '{content}',
        content: {
          'multiline': 'First line\nSecond line',
          'literal': r'Keep \n literally',
        },
        targetLanguage: '日本語',
      );

      expect(result, contains(r'multiline: "First line\nSecond line"'));
      expect(result, contains(r'literal: "Keep \\n literally"'));
    });
  });
}
