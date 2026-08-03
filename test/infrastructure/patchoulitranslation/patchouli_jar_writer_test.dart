import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:villager_translator/infrastructure/patchoulitranslation/patchouli_jar_writer.dart';

import '../../test_support/fake_jar_builder.dart';

Future<Map<String, String>> _readAllText(File jarFile) async {
  final bytes = await jarFile.readAsBytes();
  final archive = ZipDecoder().decodeBytes(bytes);
  return {
    for (final file in archive.files)
      if (file.isFile) file.name: utf8.decode(file.content),
  };
}

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('patchouli_jar_writer_');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('新規エントリが追加され、既存エントリ(翻訳対象以外)は破損・欠落しない(受け入れ条件8)', () async {
    final jarFile = File(p.join(tempDir.path, 'guidemod.jar'));
    await writeFakeJar(jarFile, {
      'fabric.mod.json':
          '{"id": "guidemod", "name": "Guide Mod", "version": "1.0"}',
      'assets/guidemod/patchouli_books/guide/en_us/book.json':
          '{"name": "Example Guide"}',
    });

    await writePatchouliTranslationsToJar(
      jarFile: jarFile,
      newEntries: {
        'assets/guidemod/patchouli_books/guide/ja_jp/book.json':
            '{"name": "サンプルガイド"}',
      },
    );

    final contents = await _readAllText(jarFile);
    expect(
      contents['fabric.mod.json'],
      '{"id": "guidemod", "name": "Guide Mod", "version": "1.0"}',
    );
    expect(
      contents['assets/guidemod/patchouli_books/guide/en_us/book.json'],
      '{"name": "Example Guide"}',
    );
    expect(
      contents['assets/guidemod/patchouli_books/guide/ja_jp/book.json'],
      '{"name": "サンプルガイド"}',
    );
  });

  test('同じパスの既存エントリは上書きされる', () async {
    final jarFile = File(p.join(tempDir.path, 'guidemod.jar'));
    await writeFakeJar(jarFile, {
      'assets/guidemod/patchouli_books/guide/ja_jp/book.json':
          '{"name": "古い翻訳"}',
    });

    await writePatchouliTranslationsToJar(
      jarFile: jarFile,
      newEntries: {
        'assets/guidemod/patchouli_books/guide/ja_jp/book.json':
            '{"name": "新しい翻訳"}',
      },
    );

    final contents = await _readAllText(jarFile);
    expect(
      contents['assets/guidemod/patchouli_books/guide/ja_jp/book.json'],
      '{"name": "新しい翻訳"}',
    );
    expect(contents.length, 1);
  });

  test('書き込み後、一時ファイルが残らない', () async {
    final jarFile = File(p.join(tempDir.path, 'guidemod.jar'));
    await writeFakeJar(jarFile, {'a.json': '{"a": "A"}'});

    await writePatchouliTranslationsToJar(
      jarFile: jarFile,
      newEntries: {'b.json': '{"b": "B"}'},
    );

    final tempFile = File('${jarFile.path}.tmp');
    expect(await tempFile.exists(), isFalse);
    expect(await jarFile.exists(), isTrue);
  });
}
