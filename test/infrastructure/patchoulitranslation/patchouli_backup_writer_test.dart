import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:villager_translator/infrastructure/patchoulitranslation/patchouli_backup_writer.dart';

import '../../test_support/fake_jar_builder.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('patchouli_backup_test_');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test(
    'JAR 書き込み前に logs/localizer/{sessionId}/backup/patchouli_jar/ へ原本がバックアップされる(受け入れ条件9)',
    () async {
      final jarFile = File(p.join(tempDir.path, 'mods', 'guidemod.jar'));
      await writeFakeJar(jarFile, {
        'assets/guidemod/patchouli_books/guide/en_us/book.json':
            '{"name": "Example Guide"}',
      });

      final backupDirectory = await backupPatchouliJars(
        profileDirectory: tempDir,
        jarRelativePaths: ['guidemod.jar'],
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
          'patchouli_jar',
        ]),
      );

      final backedUpFile = File(p.join(backupDirectory.path, 'guidemod.jar'));
      expect(await backedUpFile.exists(), isTrue);
      expect(
        await backedUpFile.readAsBytes(),
        equals(await jarFile.readAsBytes()),
      );

      // JAR 書き換え後でも、バックアップから原本が復元可能であることを確認する。
      await jarFile.writeAsBytes([1, 2, 3]);
      expect(
        await backedUpFile.readAsBytes(),
        isNot(equals(await jarFile.readAsBytes())),
      );
    },
  );

  test('重複した JAR 相対パスは1回だけバックアップされる', () async {
    await writeFakeJar(File(p.join(tempDir.path, 'mods', 'guidemod.jar')), {
      'assets/guidemod/patchouli_books/guide/en_us/book.json': '{"name": "A"}',
    });

    final backupDirectory = await backupPatchouliJars(
      profileDirectory: tempDir,
      jarRelativePaths: ['guidemod.jar', 'guidemod.jar'],
      sessionId: '20260803-120001',
    );

    final backedUpFile = File(p.join(backupDirectory.path, 'guidemod.jar'));
    expect(await backedUpFile.exists(), isTrue);
  });
}
