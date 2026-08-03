import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:villager_translator/domain/questtranslation/quest_output_builder.dart';
import 'package:villager_translator/infrastructure/questtranslation/quest_output_writer.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('quest_output_writer_test_');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('相対パスに従って複数ファイルを書き出す', () async {
    final written = await writeQuestOutputFiles(
      profileDirectory: tempDir,
      files: const [
        QuestOutputFile(
          relativePath: 'kubejs/assets/kubejs/lang/ja_jp.json',
          content: '{"a":"1"}',
        ),
        QuestOutputFile(
          relativePath: 'kubejs/assets/ftbquests/lang/ja_jp.json',
          content: '{"a":"1"}',
        ),
      ],
    );

    expect(written, hasLength(2));
    expect(
      await File(
        p.joinAll([tempDir.path, 'kubejs', 'assets', 'kubejs', 'lang', 'ja_jp.json']),
      ).readAsString(),
      '{"a":"1"}',
    );
    expect(
      await File(
        p.joinAll([tempDir.path, 'kubejs', 'assets', 'ftbquests', 'lang', 'ja_jp.json']),
      ).readAsString(),
      '{"a":"1"}',
    );
  });

  test('原本と同じ相対パスを指定すると上書きになる(SNBT の直接上書き、受け入れ条件5)', () async {
    final original = File(
      p.join(tempDir.path, 'config', 'ftbquests', 'quests', 'a.snbt'),
    );
    await original.parent.create(recursive: true);
    await original.writeAsString('title: "Original"');

    await writeQuestOutputFiles(
      profileDirectory: tempDir,
      files: const [
        QuestOutputFile(
          relativePath: 'config/ftbquests/quests/a.snbt',
          content: 'title: "Translated"',
        ),
      ],
    );

    expect(await original.readAsString(), 'title: "Translated"');
    // 言語サフィックス付きの別ファイルは作られない。
    expect(
      await Directory(p.join(tempDir.path, 'config', 'ftbquests', 'quests')).list().length,
      1,
    );
  });
}
