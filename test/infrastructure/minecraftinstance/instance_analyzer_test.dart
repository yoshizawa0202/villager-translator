import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:villager_translator/domain/minecraftinstance/instance_analysis.dart';
import 'package:villager_translator/domain/minecraftinstance/minecraft_instance.dart';
import 'package:villager_translator/domain/minecraftinstance/minecraft_launcher.dart';
import 'package:villager_translator/domain/minecraftinstance/mod_loader.dart';
import 'package:villager_translator/infrastructure/minecraftinstance/instance_analyzer.dart';

import '../../test_support/fake_jar_builder.dart';

MinecraftInstance _instance(Directory root, {String? minecraftVersion}) =>
    MinecraftInstance(
      id: buildInstanceId(MinecraftLauncher.manual, root.path),
      name: 'Test Pack',
      launcher: MinecraftLauncher.manual,
      rootPath: root.path,
      minecraftVersion: minecraftVersion,
    );

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('instance_analyzer_test_');
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  test('既存の 3 スキャナで翻訳対象を解析する(011 AC-15)', () async {
    await writeFakeJar(File(p.join(tempDir.path, 'mods', 'moda.jar')), {
      'fabric.mod.json': '{"id": "moda", "name": "Mod A", "version": "1.0"}',
      'assets/moda/lang/en_us.json': '{"item.a": "Item A"}',
    });
    await writeFakeJar(File(p.join(tempDir.path, 'mods', 'modb.jar')), {
      'fabric.mod.json': '{"id": "modb", "name": "Mod B", "version": "1.0"}',
      'assets/modb/lang/en_us.json': '{"item.b": "Item B"}',
      'assets/modb/lang/ja_jp.json': '{"item.b": "アイテムB"}',
    });
    await File(
          p.join(
            tempDir.path,
            'kubejs',
            'assets',
            'kubejs',
            'lang',
            'en_us.json',
          ),
        )
        .create(recursive: true)
        .then((f) => f.writeAsString('{"q.1": "Quest 1"}'));

    final analysis = await const InstanceAnalyzer().analyze(
      instance: _instance(tempDir, minecraftVersion: '1.20.1'),
      targetLanguageId: 'ja_jp',
    );

    expect(analysis.modJarCount, 2);
    expect(analysis.translatableModCount, 2);
    // 翻訳済み・未翻訳の内訳は hasExistingTranslation から集計する(011 §16)。
    expect(analysis.translatedModCount, 1);
    expect(analysis.untranslatedModCount, 1);

    final ftb = analysis.questSummaries.firstWhere(
      (s) => s.family == QuestFamily.ftbQuests,
    );
    expect(ftb.detected, isTrue);
    expect(ftb.stringCount, 1);

    final betterQuesting = analysis.questSummaries.firstWhere(
      (s) => s.family == QuestFamily.betterQuesting,
    );
    expect(betterQuesting.detected, isFalse);
  });

  test('mods/ が無いインスタンスでも解析できる(件数 0)', () async {
    await Directory(p.join(tempDir.path, 'config')).create(recursive: true);

    final analysis = await const InstanceAnalyzer().analyze(
      instance: _instance(tempDir),
      targetLanguageId: 'ja_jp',
    );

    expect(analysis.modJarCount, 0);
    expect(analysis.isEmpty, isTrue);
  });

  test('ランチャーメタデータで埋まらない値を JAR から補完する(011 §12 の第3段)', () async {
    await writeFakeJar(File(p.join(tempDir.path, 'mods', 'moda.jar')), {
      'fabric.mod.json':
          '{"id": "moda", "name": "Mod A", "version": "1.0", '
          '"depends": {"minecraft": ">=1.20.1 <1.21"}}',
      'assets/moda/lang/en_us.json': '{"item.a": "Item A"}',
    });

    final analysis = await const InstanceAnalyzer().analyze(
      instance: _instance(tempDir),
      targetLanguageId: 'ja_jp',
    );

    expect(analysis.instance.minecraftVersion, '1.20.1');
    expect(analysis.instance.modLoader, ModLoader.fabric);
  });

  test('インスタンスが削除されていた場合は日本語のエラーで失敗する(011 AC-21)', () async {
    final missing = Directory(p.join(tempDir.path, 'missing'));

    expect(
      () => const InstanceAnalyzer().analyze(
        instance: _instance(missing),
        targetLanguageId: 'ja_jp',
      ),
      throwsA(
        isA<InstanceNotFoundException>().having(
          (e) => e.toString(),
          'toString',
          contains('見つかりません'),
        ),
      ),
    );
  });
}
