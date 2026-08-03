import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:villager_translator/infrastructure/modtranslation/resource_pack_writer.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp(
      'resource_pack_writer_test_',
    );
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('resourcepacks/{packName}/ 配下にファイル一式を書き出す(受け入れ条件12)', () async {
    final packDirectory = await writeResourcePack(
      profileDirectory: tempDir,
      packName: 'MyPack',
      files: {
        'pack.mcmeta': '{"pack": {"pack_format": 9}}',
        'assets/moda/lang/ja_jp.json': '{"a": "1"}',
      },
    );

    expect(packDirectory.path, p.join(tempDir.path, 'resourcepacks', 'MyPack'));
    expect(
      await File(p.join(packDirectory.path, 'pack.mcmeta')).readAsString(),
      '{"pack": {"pack_format": 9}}',
    );
    expect(
      await File(
        p.joinAll([packDirectory.path, 'assets', 'moda', 'lang', 'ja_jp.json']),
      ).readAsString(),
      '{"a": "1"}',
    );
  });
}
