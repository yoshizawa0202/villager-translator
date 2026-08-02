import 'package:flutter_test/flutter_test.dart';
import 'package:villager_translator/domain/llm/response_parser.dart';

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
  });
}
