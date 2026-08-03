import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:villager_translator/domain/modtranslation/mod_scan_entry.dart';
import 'package:villager_translator/infrastructure/modtranslation/mod_directory_scanner.dart';

import '../../test_support/fake_jar_builder.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('mod_scanner_test_');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test(
    'fabric.mod.json → mods.toml → MANIFEST.MF の優先順で MOD 情報を取得する(受け入れ条件1)',
    () async {
      await writeFakeJar(File(p.join(tempDir.path, 'mods', 'fabric.jar')), {
        'fabric.mod.json':
            '{"id": "fabricmod", "name": "Fabric Mod", "version": "1.0"}',
        'assets/fabricmod/lang/en_us.json': '{"a": "A"}',
      });
      await writeFakeJar(File(p.join(tempDir.path, 'mods', 'forge.jar')), {
        'META-INF/mods.toml':
            '[[mods]]\nmodId="forgemod"\ndisplayName="Forge Mod"\nversion="2.0"',
        'assets/forgemod/lang/en_us.json': '{"a": "A"}',
      });
      await writeFakeJar(
        File(p.join(tempDir.path, 'mods', 'manifestonly.jar')),
        {
          'META-INF/MANIFEST.MF': 'Manifest-Version: 1.0',
          'assets/manifestonly/lang/en_us.json': '{"a": "A"}',
        },
      );

      final result = await scanModsDirectory(
        profileDirectory: tempDir,
        targetLanguageId: 'ja_jp',
      );

      expect(result.entries, hasLength(3));
      final byId = {for (final e in result.entries) e.jarRelativePath: e};
      expect(byId['fabric.jar']!.modInfo.id, 'fabricmod');
      expect(byId['forge.jar']!.modInfo.id, 'forgemod');
      expect(byId['manifestonly.jar']!.modInfo.id, 'unknown');
    },
  );

  test('MOD 情報を取得できない JAR はスキップされ、ログに記録される(受け入れ条件2)', () async {
    await writeFakeJar(File(p.join(tempDir.path, 'mods', 'noinfo.jar')), {
      'assets/noinfo/lang/en_us.json': '{"a": "A"}',
    });

    final skips = <ModScanSkip>[];
    final result = await scanModsDirectory(
      profileDirectory: tempDir,
      targetLanguageId: 'ja_jp',
      onSkip: skips.add,
    );

    expect(result.entries, isEmpty);
    expect(skips, hasLength(1));
    expect(skips.single.reason, ModScanSkipReason.noModInfo);
  });

  test('lang ファイルを含まない MOD は対象一覧から除外される(受け入れ条件3)', () async {
    await writeFakeJar(File(p.join(tempDir.path, 'mods', 'nolang.jar')), {
      'fabric.mod.json': '{"id": "nolang", "name": "NoLang", "version": "1.0"}',
    });

    final result = await scanModsDirectory(
      profileDirectory: tempDir,
      targetLanguageId: 'ja_jp',
    );

    expect(result.entries, isEmpty);
  });

  test('壊れた JAR が1件あっても他の MOD のスキャンが継続される(受け入れ条件5)', () async {
    await File(
      p.join(tempDir.path, 'mods', 'broken.jar'),
    ).create(recursive: true);
    await File(
      p.join(tempDir.path, 'mods', 'broken.jar'),
    ).writeAsBytes([1, 2, 3, 4]);

    await writeFakeJar(File(p.join(tempDir.path, 'mods', 'ok.jar')), {
      'fabric.mod.json': '{"id": "okmod", "name": "OK", "version": "1.0"}',
      'assets/okmod/lang/en_us.json': '{"a": "A"}',
    });

    final skips = <ModScanSkip>[];
    final result = await scanModsDirectory(
      profileDirectory: tempDir,
      targetLanguageId: 'ja_jp',
      onSkip: skips.add,
    );

    expect(result.entries, hasLength(1));
    expect(result.entries.single.modInfo.id, 'okmod');
    expect(skips.any((s) => s.jarRelativePath == 'broken.jar'), isTrue);
  });

  test('翻訳処理(スキャン)の前後で元の .jar ファイルの内容が変化しない(受け入れ条件14)', () async {
    final jarFile = File(p.join(tempDir.path, 'mods', 'unchanged.jar'));
    await writeFakeJar(jarFile, {
      'fabric.mod.json': '{"id": "unchanged", "name": "U", "version": "1.0"}',
      'assets/unchanged/lang/en_us.json': '{"a": "A"}',
    });

    final beforeBytes = await jarFile.readAsBytes();

    await scanModsDirectory(
      profileDirectory: tempDir,
      targetLanguageId: 'ja_jp',
    );

    final afterBytes = await jarFile.readAsBytes();
    expect(afterBytes, equals(beforeBytes));
  });

  test('mods/ ディレクトリが存在しない場合は空の結果を返す', () async {
    final result = await scanModsDirectory(
      profileDirectory: tempDir,
      targetLanguageId: 'ja_jp',
    );

    expect(result.entries, isEmpty);
    expect(result.skips, isEmpty);
  });
}
