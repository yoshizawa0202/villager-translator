import 'package:flutter_test/flutter_test.dart';
import 'package:villager_translator/domain/questtranslation/quest_lang_scan.dart';

void main() {
  group('isAlreadyTranslatedLangFileName', () {
    test('言語コードサフィックスを持つファイル名は翻訳済みと判定する', () {
      expect(isAlreadyTranslatedLangFileName('en_us.ja_jp.json'), isTrue);
      expect(isAlreadyTranslatedLangFileName('en_us.zh_cn.json'), isTrue);
    });

    test('原文ファイル名(単一の言語コードのみ)は翻訳済みと判定しない', () {
      expect(isAlreadyTranslatedLangFileName('en_us.json'), isFalse);
    });

    test('json 以外の拡張子は対象外', () {
      expect(isAlreadyTranslatedLangFileName('en_us.ja_jp.lang'), isFalse);
    });

    test('言語コードに見えないサフィックスは翻訳済みと判定しない', () {
      expect(isAlreadyTranslatedLangFileName('quests.custom.json'), isFalse);
    });
  });

  group('listCandidateLangJsonBasenames', () {
    test('翻訳済みパターンを除外し、json 以外・アルファベット順で返す(受け入れ条件1)', () {
      final result = listCandidateLangJsonBasenames([
        'en_us.json',
        'en_us.ja_jp.json',
        'readme.txt',
        'quests.json',
      ]);

      expect(result, ['en_us.json', 'quests.json']);
    });
  });
}
