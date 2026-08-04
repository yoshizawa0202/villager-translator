import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:villager_translator/domain/customfiletranslation/json_flattener.dart';

void main() {
  group('flattenJsonStrings', () {
    test('ネストしたオブジェクト・配列がドット/ブラケット記法にフラット化される(受け入れ条件3)', () {
      final root = jsonDecode('{"a": {"b": ["x", "y", {"c": "z"}]}}');

      final result = flattenJsonStrings(root);

      expect(result, {'a.b[0]': 'x', 'a.b[1]': 'y', 'a.b[2].c': 'z'});
    });

    test('文字列の葉ノードのみが対象に含まれ、非文字列は除外される(受け入れ条件4)', () {
      final root = jsonDecode(
        '{"title": "Hello", "count": 42, "enabled": true, "note": null}',
      );

      final result = flattenJsonStrings(root);

      expect(result, {'title': 'Hello'});
    });

    test('トップレベルが配列でもブラケット記法でフラット化される', () {
      final root = jsonDecode('["first", "second"]');

      final result = flattenJsonStrings(root);

      expect(result, {'[0]': 'first', '[1]': 'second'});
    });
  });

  group('rebuildJsonWithTranslations', () {
    test('翻訳結果を差し戻すと構造・キー順序・非文字列値が保持される(受け入れ条件5)', () {
      final root =
          jsonDecode(
                '{"a": {"b": ["x", "y", {"c": "z"}]}, "count": 42, "flag": true, "n": null}',
              )
              as Map<String, dynamic>;

      final rebuilt = rebuildJsonWithTranslations(root, {
        'a.b[0]': '訳x',
        'a.b[1]': '訳y',
        'a.b[2].c': '訳z',
      });

      expect(rebuilt, {
        'a': {
          'b': [
            '訳x',
            '訳y',
            {'c': '訳z'},
          ],
        },
        'count': 42,
        'flag': true,
        'n': null,
      });
      // キー順序も保持される。
      expect((rebuilt as Map).keys.toList(), ['a', 'count', 'flag', 'n']);
    });

    test('対応する翻訳結果がない文字列は元の値のまま残る(部分成功時のフォールバック)', () {
      final root = jsonDecode('{"a": "original-a", "b": "original-b"}');

      final rebuilt = rebuildJsonWithTranslations(root, {'a': '訳a'});

      expect(rebuilt, {'a': '訳a', 'b': 'original-b'});
    });
  });
}
