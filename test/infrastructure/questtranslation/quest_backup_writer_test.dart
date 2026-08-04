import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:villager_translator/domain/questtranslation/quest_scan_entry.dart';
import 'package:villager_translator/infrastructure/questtranslation/quest_backup_writer.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('quest_backup_test_');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('選択した SNBT ファイルが logs/localizer/{sessionId}/backup/snbt_original/ 配下へ、'
      '相対パス構造を維持したままバックアップされる(受け入れ条件6)', () async {
    final original = File(
      p.join(
        tempDir.path,
        'config',
        'ftbquests',
        'quests',
        'chapter',
        'a.snbt',
      ),
    );
    await original.parent.create(recursive: true);
    await original.writeAsString('title: "Original"');

    final entry = QuestScanEntry(
      format: QuestFormat.ftbQuestsSnbt,
      relativePath: 'config/ftbquests/quests/chapter/a.snbt',
      sourceEntries: const {'0': 'Original'},
      snbtOriginalContent: 'title: "Original"',
      snbtSpans: const [],
    );

    final backupDirectory = await backupSnbtOriginals(
      profileDirectory: tempDir,
      entries: [entry],
      sessionId: '20260803-120000',
    );

    expect(
      backupDirectory.path,
      p.joinAll([
        tempDir.path,
        'logs',
        'localizer',
        '20260803-120000',
        'backup',
        'snbt_original',
      ]),
    );

    final backedUpFile = File(
      p.joinAll([
        backupDirectory.path,
        'config',
        'ftbquests',
        'quests',
        'chapter',
        'a.snbt',
      ]),
    );
    expect(await backedUpFile.exists(), isTrue);
    expect(await backedUpFile.readAsString(), 'title: "Original"');

    // 翻訳(上書き)後でも、バックアップから原本相当が復元可能であることを確認する。
    await original.writeAsString('title: "Translated"');
    expect(await backedUpFile.readAsString(), 'title: "Original"');
  });
}
