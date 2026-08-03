import 'package:flutter_test/flutter_test.dart';
import 'package:villager_translator/domain/questtranslation/quest_output_builder.dart';
import 'package:villager_translator/domain/questtranslation/quest_scan_entry.dart';
import 'package:villager_translator/domain/questtranslation/quest_translation_service.dart';
import 'package:villager_translator/domain/questtranslation/snbt_extractor.dart';

void main() {
  group('buildQuestOutputFiles', () {
    test('KubeJS lang は kubejs と ftbquests の両方に同一内容で出力される(受け入れ条件2)', () {
      final entry = QuestScanEntry(
        format: QuestFormat.ftbQuestsKubejsLang,
        relativePath: 'kubejs/assets/kubejs/lang/en_us.json',
        sourceEntries: const {'a': '1'},
      );
      final output = QuestTranslationOutput(
        entry: entry,
        entries: {'b': '2', 'a': '1'},
      );

      final files = buildQuestOutputFiles(output, 'ja_jp');

      expect(files, hasLength(2));
      expect(files[0].relativePath, 'kubejs/assets/kubejs/lang/ja_jp.json');
      expect(files[1].relativePath, 'kubejs/assets/ftbquests/lang/ja_jp.json');
      expect(files[0].content, files[1].content);
      // キーがソートされている(受け入れ条件9)。
      expect(files[0].content.indexOf('"a"'), lessThan(files[0].content.indexOf('"b"')));
    });

    test('SNBT は同一パスへ上書きする内容を返す(受け入れ条件5)', () {
      const original = 'title: "Hello"';
      final unit = buildSnbtTranslationUnit(original);
      final entry = QuestScanEntry(
        format: QuestFormat.ftbQuestsSnbt,
        relativePath: 'config/ftbquests/quests/chapter.snbt',
        sourceEntries: unit.entries,
        snbtOriginalContent: unit.originalContent,
        snbtSpans: unit.spans,
      );
      final output = QuestTranslationOutput(
        entry: entry,
        entries: {'0': 'こんにちは'},
      );

      final files = buildQuestOutputFiles(output, 'ja_jp');

      expect(files, hasLength(1));
      expect(files.single.relativePath, entry.relativePath);
      expect(files.single.content, 'title: "こんにちは"');
    });

    test('Better Quests 標準は {basename}.{lang}.json として出力される(受け入れ条件7)', () {
      final entry = QuestScanEntry(
        format: QuestFormat.betterQuestingStandard,
        relativePath: 'resources/betterquesting/lang/en_us.json',
        sourceEntries: const {'a': '1'},
      );
      final output = QuestTranslationOutput(
        entry: entry,
        entries: {'a': '1訳'},
      );

      final files = buildQuestOutputFiles(output, 'ja_jp');

      expect(files.single.relativePath, 'resources/betterquesting/lang/en_us.ja_jp.json');
    });

    test('Better Quests 直接は DefaultQuests.{lang}.lang として出力される(受け入れ条件8)', () {
      final entry = QuestScanEntry(
        format: QuestFormat.betterQuestingDirect,
        relativePath: 'config/betterquesting/DefaultQuests.lang',
        sourceEntries: const {'b': '2', 'a': '1'},
      );
      final output = QuestTranslationOutput(
        entry: entry,
        entries: {'b': '2訳', 'a': '1訳'},
      );

      final files = buildQuestOutputFiles(output, 'ja_jp');

      expect(files.single.relativePath, 'config/betterquesting/DefaultQuests.ja_jp.lang');
      // .lang はキーのソート順で key=value 再シリアライズされる(受け入れ条件9)。
      expect(files.single.content, 'a=1訳\nb=2訳');
    });
  });

  group('existingTranslationCheckPath', () {
    test('SNBT は常に null(判定不能、受け入れ条件11)', () {
      final entry = QuestScanEntry(
        format: QuestFormat.ftbQuestsSnbt,
        relativePath: 'config/ftbquests/quests/chapter.snbt',
        sourceEntries: const {},
        snbtOriginalContent: '',
        snbtSpans: const [],
      );
      expect(existingTranslationCheckPath(entry, 'ja_jp'), isNull);
    });

    test('KubeJS lang は kubejs パスを返す', () {
      final entry = QuestScanEntry(
        format: QuestFormat.ftbQuestsKubejsLang,
        relativePath: 'kubejs/assets/kubejs/lang/en_us.json',
        sourceEntries: const {},
      );
      expect(
        existingTranslationCheckPath(entry, 'ja_jp'),
        'kubejs/assets/kubejs/lang/ja_jp.json',
      );
    });

    test('Better Quests 標準は隣接する {stem}.{lang}.json を返す', () {
      final entry = QuestScanEntry(
        format: QuestFormat.betterQuestingStandard,
        relativePath: 'resources/betterquesting/lang/en_us.json',
        sourceEntries: const {},
      );
      expect(
        existingTranslationCheckPath(entry, 'ja_jp'),
        'resources/betterquesting/lang/en_us.ja_jp.json',
      );
    });

    test('Better Quests 直接は隣接する DefaultQuests.{lang}.lang を返す', () {
      final entry = QuestScanEntry(
        format: QuestFormat.betterQuestingDirect,
        relativePath: 'config/betterquesting/DefaultQuests.lang',
        sourceEntries: const {},
      );
      expect(
        existingTranslationCheckPath(entry, 'ja_jp'),
        'config/betterquesting/DefaultQuests.ja_jp.lang',
      );
    });
  });
}
