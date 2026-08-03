import 'package:flutter_test/flutter_test.dart';
import 'package:villager_translator/domain/translation/lang_codec.dart';

void main() {
  group('decodeLangJson', () {
    test('_comment キーを除去してパースする', () {
      final result = decodeLangJson(
        '{"_comment": "説明", "item.example.name": "Example Item"}',
      );

      expect(result, {'item.example.name': 'Example Item'});
    });

    test('BOM・制御文字を除去してパースする', () {
      final raw = '﻿{"key": "value"}';
      final result = decodeLangJson(raw);

      expect(result, {'key': 'value'});
    });

    test('壊れた JSON は FormatException を投げる', () {
      expect(() => decodeLangJson('{not valid'), throwsFormatException);
    });
  });

  group('encodeLangJson', () {
    test('キーをソートして出力する', () {
      final json = encodeLangJson({'b': '2', 'a': '1'});
      final aIndex = json.indexOf('"a"');
      final bIndex = json.indexOf('"b"');

      expect(aIndex, greaterThanOrEqualTo(0));
      expect(aIndex, lessThan(bIndex));
    });
  });

  group('decodeLangFile', () {
    test('key=value 形式をパースし、コメント行・_comment を除外する', () {
      final raw = '''
# コメント行
_comment=無視される
item.example.name=Example Item
item.example.desc=A description
''';
      final result = decodeLangFile(raw);

      expect(result, {
        'item.example.name': 'Example Item',
        'item.example.desc': 'A description',
      });
    });

    test('BOM・制御文字を除去してパースする', () {
      final raw = '﻿key=value\n';
      final result = decodeLangFile(raw);

      expect(result, {'key': 'value'});
    });
  });

  group('encodeLangFile', () {
    test('キーをソートして key=value 形式で出力する', () {
      final result = encodeLangFile({'b': '2', 'a': '1'});
      expect(result, 'a=1\nb=2');
    });
  });
}
