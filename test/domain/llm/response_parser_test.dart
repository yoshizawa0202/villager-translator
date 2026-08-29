import 'package:flutter_test/flutter_test.dart';
import 'package:villager_translator/domain/llm/response_parser.dart';
import 'package:villager_translator/domain/llm/translation_wire_codec.dart';

void main() {
  group('parseTranslationResponse', () {
    test('key: value 形式の行から正しいマップを復元する', () {
      final result = parseTranslationResponse(
        'greeting: こんにちは\nfarewell: さようなら',
        ['greeting', 'farewell'],
      );

      expect(result, {'greeting': 'こんにちは', 'farewell': 'さようなら'});
    });

    test('キー数が一致しない場合は FormatException を投げる', () {
      expect(
        () => parseTranslationResponse('greeting: こんにちは', [
          'greeting',
          'farewell',
        ]),
        throwsFormatException,
      );
    });

    test('行の前後に余計な空白があっても解決できる', () {
      final result = parseTranslationResponse('  greeting:   こんにちは  ', [
        'greeting',
      ]);
      expect(result, {'greeting': 'こんにちは'});
    });

    test('JSON文字列のエスケープを復号して実改行と文字列\\nを区別する', () {
      final result = parseTranslationResponse(
        r'''multiline: "1行目\n2行目"
literal: "文字列\\nのまま"
quote: "\"引用\""''',
        ['multiline', 'literal', 'quote'],
      );

      expect(result['multiline'], '1行目\n2行目');
      expect(result['literal'], r'文字列\nのまま');
      expect(result['quote'], '"引用"');
    });

    test('key: value 形式で復元できない場合、Markdown装飾やヘッダー行を除去した行位置ベースの'
        'フォールバックで元のキー数と一致すれば正しく対応付けられる', () {
      const rawText = '''
## Translation Result
```
こんにちは
さようなら
```
''';

      final result = parseTranslationResponse(rawText, [
        'greeting',
        'farewell',
      ]);

      expect(result, {'greeting': 'こんにちは', 'farewell': 'さようなら'});
    });

    test('フォールバック後も行数とキー数が一致しない場合は FormatException を投げる', () {
      const rawText = '''
## Translation Result
これは1行しかありません
''';

      expect(
        () => parseTranslationResponse(rawText, ['greeting', 'farewell']),
        throwsFormatException,
      );
    });

    test('JSON文字列内へ実改行が再混入した応答は成功扱いにしない', () {
      expect(
        () => parseTranslationResponse('description: "1行目\n2行目"', [
          'description',
        ]),
        throwsFormatException,
      );
    });

    test('Iris相当の12キー・改行2値を12件として復元する', () {
      final translated = <String, String>{
        for (var i = 0; i < 12; i++)
          'iris.key.$i': i == 3 || i == 8 ? '翻訳 $i の1行目\n翻訳 $i の2行目' : '翻訳 $i',
      };
      final response = encodeTranslationContent(translated);

      final result = parseTranslationResponse(
        response,
        translated.keys.toList(),
      );

      expect(result, translated);
      expect(result, hasLength(12));
    });
  });
}
