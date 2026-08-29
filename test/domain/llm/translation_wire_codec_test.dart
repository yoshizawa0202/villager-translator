import 'package:flutter_test/flutter_test.dart';
import 'package:villager_translator/domain/llm/translation_wire_codec.dart';

void main() {
  group('translation wire codec', () {
    test('特殊文字を区別したまま1物理行1エントリへ符号化する(003 AC-14)', () {
      final content = {
        'lf': 'first\nsecond',
        'crlf': 'first\r\nsecond',
        'literal': r'first\nsecond',
        'quote': 'say "hello"',
        'backslash': r'C:\mods\example',
        'tab': 'left\tright',
        'empty': '',
      };

      final encoded = encodeTranslationContent(content);

      expect(encoded.split('\n'), hasLength(content.length));
      expect(encoded, contains(r'lf: "first\nsecond"'));
      expect(encoded, contains(r'crlf: "first\r\nsecond"'));
      expect(encoded, contains(r'literal: "first\\nsecond"'));
      expect(encoded, contains(r'quote: "say \"hello\""'));
      expect(encoded, contains(r'backslash: "C:\\mods\\example"'));
      expect(encoded, contains(r'tab: "left\tright"'));
      expect(encoded, contains('empty: ""'));
    });

    test('JSON文字列と従来の引用符なし値を復号する', () {
      expect(decodeTranslationValue(r'"1行目\n2行目"'), '1行目\n2行目');
      expect(decodeTranslationValue('従来形式'), '従来形式');
    });

    test('引用符で始まる不正なJSON文字列は受理しない', () {
      expect(() => decodeTranslationValue('"閉じていない'), throwsFormatException);
    });
  });
}
