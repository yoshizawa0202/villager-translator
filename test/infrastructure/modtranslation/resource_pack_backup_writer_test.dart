import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:villager_translator/infrastructure/modtranslation/resource_pack_backup_writer.dart';
import 'package:villager_translator/infrastructure/modtranslation/resource_pack_writer.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp(
      'resource_pack_backup_test_',
    );
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test(
    '生成したリソースパック一式が logs/localizer/{sessionId}/backup/resource_pack/ 配下にコピーされる(受け入れ条件15)',
    () async {
      final packDirectory = await writeResourcePack(
        profileDirectory: tempDir,
        packName: 'MyPack',
        files: {
          'pack.mcmeta': '{"pack": {"pack_format": 9}}',
          'assets/moda/lang/ja_jp.json': '{"a": "1"}',
        },
      );

      final backupDirectory = await backupResourcePack(
        profileDirectory: tempDir,
        packDirectory: packDirectory,
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
          'resource_pack',
        ]),
      );
      expect(
        await File(p.join(backupDirectory.path, 'pack.mcmeta')).readAsString(),
        '{"pack": {"pack_format": 9}}',
      );
      expect(
        await File(
          p.joinAll([
            backupDirectory.path,
            'assets',
            'moda',
            'lang',
            'ja_jp.json',
          ]),
        ).readAsString(),
        '{"a": "1"}',
      );
    },
  );
}
