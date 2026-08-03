import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:villager_translator/domain/questtranslation/quest_scan_entry.dart';
import 'package:villager_translator/infrastructure/questtranslation/quest_directory_scanner.dart';

Future<void> _writeFile(String path, String content) async {
  final file = File(path);
  await file.parent.create(recursive: true);
  await file.writeAsString(content);
}

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('quest_scanner_test_');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test(
    'kubejs/assets/kubejs/lang/en_us.json があれば、翻訳済みパターンを除く *.json が KubeJS lang として検出される(受け入れ条件1)',
    () async {
      await _writeFile(
        p.join(tempDir.path, 'kubejs', 'assets', 'kubejs', 'lang', 'en_us.json'),
        '{"quest.a": "Quest A"}',
      );
      await _writeFile(
        p.join(
          tempDir.path,
          'kubejs',
          'assets',
          'kubejs',
          'lang',
          'en_us.ja_jp.json',
        ),
        '{"quest.a": "既存訳"}',
      );

      final entries = await scanQuestsDirectory(profileDirectory: tempDir);

      final kubejsEntries = entries
          .where((e) => e.format == QuestFormat.ftbQuestsKubejsLang)
          .toList();
      expect(kubejsEntries, hasLength(1));
      expect(
        kubejsEntries.single.relativePath,
        'kubejs/assets/kubejs/lang/en_us.json',
      );
      expect(kubejsEntries.single.sourceEntries, {'quest.a': 'Quest A'});
    },
  );

  test(
    'KubeJS lang が存在しない場合、quests → normal → 直下の順に存在する最初のディレクトリの *.snbt が再帰的に検出される(受け入れ条件3)',
    () async {
      // quests は存在しないので normal が使われるはず。
      await _writeFile(
        p.join(
          tempDir.path,
          'config',
          'ftbquests',
          'normal',
          'chapters',
          'chapter1.snbt',
        ),
        'title: "Chapter 1"',
      );
      // フォールバック(直下)にもファイルを置くが、normal が優先されるため検出されないはず。
      await _writeFile(
        p.join(tempDir.path, 'config', 'ftbquests', 'fallback.snbt'),
        'title: "Should not be picked"',
      );

      final entries = await scanQuestsDirectory(profileDirectory: tempDir);

      final snbtEntries = entries
          .where((e) => e.format == QuestFormat.ftbQuestsSnbt)
          .toList();
      expect(snbtEntries, hasLength(1));
      expect(
        snbtEntries.single.relativePath,
        'config/ftbquests/normal/chapters/chapter1.snbt',
      );
      expect(snbtEntries.single.sourceEntries, {'0': 'Chapter 1'});
    },
  );

  test('quests ディレクトリが存在すれば normal より優先される', () async {
    await _writeFile(
      p.join(tempDir.path, 'config', 'ftbquests', 'quests', 'a.snbt'),
      'title: "A"',
    );
    await _writeFile(
      p.join(tempDir.path, 'config', 'ftbquests', 'normal', 'b.snbt'),
      'title: "B"',
    );

    final entries = await scanQuestsDirectory(profileDirectory: tempDir);
    final snbtEntries = entries
        .where((e) => e.format == QuestFormat.ftbQuestsSnbt)
        .toList();

    expect(snbtEntries, hasLength(1));
    expect(snbtEntries.single.relativePath, 'config/ftbquests/quests/a.snbt');
  });

  test('resources/betterquesting/lang/*.json が標準形式として検出される', () async {
    await _writeFile(
      p.join(tempDir.path, 'resources', 'betterquesting', 'lang', 'en_us.json'),
      '{"quest.b": "Quest B"}',
    );

    final entries = await scanQuestsDirectory(profileDirectory: tempDir);
    final bqEntries = entries
        .where((e) => e.format == QuestFormat.betterQuestingStandard)
        .toList();

    expect(bqEntries, hasLength(1));
    expect(
      bqEntries.single.relativePath,
      'resources/betterquesting/lang/en_us.json',
    );
  });

  test('config/betterquesting/DefaultQuests.lang が直接形式として検出される', () async {
    await _writeFile(
      p.join(tempDir.path, 'config', 'betterquesting', 'DefaultQuests.lang'),
      'quest.c=Quest C',
    );

    final entries = await scanQuestsDirectory(profileDirectory: tempDir);
    final directEntries = entries
        .where((e) => e.format == QuestFormat.betterQuestingDirect)
        .toList();

    expect(directEntries, hasLength(1));
    expect(directEntries.single.sourceEntries, {'quest.c': 'Quest C'});
  });

  test('FTB Quests と Better Quests は独立して同時に検出される', () async {
    await _writeFile(
      p.join(tempDir.path, 'kubejs', 'assets', 'kubejs', 'lang', 'en_us.json'),
      '{"a": "A"}',
    );
    await _writeFile(
      p.join(tempDir.path, 'resources', 'betterquesting', 'lang', 'en_us.json'),
      '{"b": "B"}',
    );
    await _writeFile(
      p.join(tempDir.path, 'config', 'betterquesting', 'DefaultQuests.lang'),
      'c=C',
    );

    final entries = await scanQuestsDirectory(profileDirectory: tempDir);

    expect(
      entries.map((e) => e.format).toSet(),
      {
        QuestFormat.ftbQuestsKubejsLang,
        QuestFormat.betterQuestingStandard,
        QuestFormat.betterQuestingDirect,
      },
    );
  });

  test('何も存在しない場合は空リストを返す', () async {
    final entries = await scanQuestsDirectory(profileDirectory: tempDir);
    expect(entries, isEmpty);
  });
}
