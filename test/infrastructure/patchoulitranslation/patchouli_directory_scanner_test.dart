import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:villager_translator/domain/patchoulitranslation/patchouli_book_entry.dart';
import 'package:villager_translator/infrastructure/patchoulitranslation/patchouli_directory_scanner.dart';

import '../../test_support/fake_jar_builder.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('patchouli_scanner_test_');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('MOD スキャン(004)と同じ mods/ 配下の JAR 一覧を対象にする(受け入れ条件2)', () async {
    await writeFakeJar(File(p.join(tempDir.path, 'mods', 'guidemod.jar')), {
      'assets/guidemod/patchouli_books/guide/en_us/book.json':
          '{"name": "Example Guide"}',
      'assets/guidemod/patchouli_books/guide/en_us/entries/a.json':
          '{"name": "A"}',
    });
    await writeFakeJar(File(p.join(tempDir.path, 'mods', 'nobook.jar')), {
      'fabric.mod.json': '{"id": "nobook", "name": "NoBook", "version": "1.0"}',
      'assets/nobook/lang/en_us.json': '{"a": "A"}',
    });

    final result = await scanPatchouliBooksDirectory(
      profileDirectory: tempDir,
      targetLanguageId: 'ja_jp',
    );

    expect(result.entries, hasLength(1));
    expect(result.entries.single.bookKey, 'guidemod:guide');
    expect(result.entries.single.jarRelativePath, 'guidemod.jar');
  });

  test('壊れた JAR が1件あっても他の JAR のスキャンが継続され、スキップが記録される', () async {
    // 4バイト程度の無意味なバイト列は ZipDecoder が例外を投げずに「エントリ0件」
    // として解釈してしまう(スキップにならない)ため、正当な zip を末尾切り詰めて
    // 中央ディレクトリの解決に失敗させ、確実に例外を発生させる。
    final brokenJar = File(p.join(tempDir.path, 'mods', 'broken.jar'));
    await writeFakeJar(brokenJar, {
      'assets/tmp/patchouli_books/guide/en_us/book.json': '{"name": "Tmp"}',
    });
    final validBytes = await brokenJar.readAsBytes();
    await brokenJar.writeAsBytes(validBytes.sublist(0, validBytes.length - 10));

    await writeFakeJar(File(p.join(tempDir.path, 'mods', 'ok.jar')), {
      'assets/okmod/patchouli_books/guide/en_us/book.json':
          '{"name": "OK Guide"}',
    });

    final skips = <PatchouliScanSkip>[];
    final result = await scanPatchouliBooksDirectory(
      profileDirectory: tempDir,
      targetLanguageId: 'ja_jp',
      onSkip: skips.add,
    );

    expect(result.entries, hasLength(1));
    expect(result.entries.single.bookKey, 'okmod:guide');
    expect(skips, hasLength(1));
    expect(skips.single.jarRelativePath, 'broken.jar');
    expect(skips.single.reason, PatchouliScanSkipReason.corruptJar);
  });

  test('mods/ ディレクトリが存在しない場合は空の結果を返す', () async {
    final result = await scanPatchouliBooksDirectory(
      profileDirectory: tempDir,
      targetLanguageId: 'ja_jp',
    );

    expect(result.entries, isEmpty);
    expect(result.skips, isEmpty);
  });

  test('スキャンの前後で元の .jar ファイルの内容が変化しない', () async {
    final jarFile = File(p.join(tempDir.path, 'mods', 'guidemod.jar'));
    await writeFakeJar(jarFile, {
      'assets/guidemod/patchouli_books/guide/en_us/book.json':
          '{"name": "Example Guide"}',
    });

    final beforeBytes = await jarFile.readAsBytes();

    await scanPatchouliBooksDirectory(
      profileDirectory: tempDir,
      targetLanguageId: 'ja_jp',
    );

    final afterBytes = await jarFile.readAsBytes();
    expect(afterBytes, equals(beforeBytes));
  });
}
