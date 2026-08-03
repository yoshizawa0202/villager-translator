import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:villager_translator/domain/llm/llm_adapter.dart';
import 'package:villager_translator/domain/llm/llm_adapter_config.dart';
import 'package:villager_translator/domain/llm/llm_provider.dart';
import 'package:villager_translator/domain/settings/app_settings.dart';
import 'package:villager_translator/domain/settings/existing_translation_policy.dart';
import 'package:villager_translator/infrastructure/llm/llm_adapter_factory.dart';
import 'package:villager_translator/infrastructure/llm/mock_llm_adapter.dart';
import 'package:villager_translator/infrastructure/modtranslation/mod_translation_orchestrator.dart';

import '../../test_support/fake_jar_builder.dart';

class _FakeAdapterFactory implements LlmAdapterFactory {
  @override
  LlmAdapter create(LlmProvider provider, LlmAdapterConfig config) =>
      const MockLlmAdapter();
}

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('mod_orchestrator_test_');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('スキャン→翻訳→リソースパック生成→バックアップまでの一連の流れが成功する', () async {
    await writeFakeJar(File(p.join(tempDir.path, 'mods', 'moda.jar')), {
      'fabric.mod.json': '{"id": "moda", "name": "Mod A", "version": "1.0"}',
      'assets/moda/lang/en_us.json': '{"item.a": "Item A", "item.b": "Item B"}',
    });
    await writeFakeJar(File(p.join(tempDir.path, 'mods', 'modb.jar')), {
      'fabric.mod.json': '{"id": "modb", "name": "Mod B", "version": "1.0"}',
      'assets/modb/lang/en_us.json': '{"item.c": "Item C", "item.d": "Item D"}',
      'assets/modb/lang/ja_jp.json': '{"item.c": "手動修正済みの翻訳"}',
    });

    final beforeBytesA = await File(
      p.join(tempDir.path, 'mods', 'moda.jar'),
    ).readAsBytes();
    final beforeBytesB = await File(
      p.join(tempDir.path, 'mods', 'modb.jar'),
    ).readAsBytes();

    final orchestrator = ModTranslationOrchestrator(
      adapterFactory: _FakeAdapterFactory(),
    );

    final scanResult = await orchestrator.scan(
      profileDirectory: tempDir,
      targetLanguageId: 'ja_jp',
    );
    expect(scanResult.entries, hasLength(2));

    final settings = AppSettings.defaults().copyWith(
      translation: AppSettings.defaults().translation.copyWith(
        existingTranslationPolicy: ExistingTranslationPolicy.diffUpdate,
      ),
    );

    final result = await orchestrator.translateAndPack(
      profileDirectory: tempDir,
      selectedEntries: scanResult.entries,
      targetLanguageId: 'ja_jp',
      targetLanguageDisplayName: '日本語',
      settings: settings,
      apiKey: 'test-key',
      sessionId: '20260803-120000',
    );

    expect(result.packDirectory, isNotNull);
    expect(result.backupDirectory, isNotNull);
    expect(result.translationResult.translatedModIds, ['moda', 'modb']);

    final packFile = File(
      p.joinAll([
        result.packDirectory!.path,
        'assets',
        'moda',
        'lang',
        'ja_jp.json',
      ]),
    );
    expect(await packFile.readAsString(), contains('[MOCK] Item A'));

    // modb は差分更新: 既存キー item.c の値は変更されず、不足キー item.d のみ翻訳される。
    final modbPackFile = File(
      p.joinAll([
        result.packDirectory!.path,
        'assets',
        'modb',
        'lang',
        'ja_jp.json',
      ]),
    );
    final modbContent = await modbPackFile.readAsString();
    expect(modbContent, contains('手動修正済みの翻訳'));
    expect(modbContent, contains('[MOCK] Item D'));

    final backupFile = File(
      p.joinAll([
        result.backupDirectory!.path,
        'assets',
        'moda',
        'lang',
        'ja_jp.json',
      ]),
    );
    expect(await backupFile.exists(), isTrue);

    // 受け入れ条件14: 元の .jar は変更されない。
    expect(
      await File(p.join(tempDir.path, 'mods', 'moda.jar')).readAsBytes(),
      equals(beforeBytesA),
    );
    expect(
      await File(p.join(tempDir.path, 'mods', 'modb.jar')).readAsBytes(),
      equals(beforeBytesB),
    );
  });

  test('全対象がスキップの場合、リソースパックが作成されない(受け入れ条件11)', () async {
    await writeFakeJar(File(p.join(tempDir.path, 'mods', 'moda.jar')), {
      'fabric.mod.json': '{"id": "moda", "name": "Mod A", "version": "1.0"}',
      'assets/moda/lang/en_us.json': '{"item.a": "Item A"}',
      'assets/moda/lang/ja_jp.json': '{"item.a": "既存訳"}',
    });

    final orchestrator = ModTranslationOrchestrator(
      adapterFactory: _FakeAdapterFactory(),
    );

    final scanResult = await orchestrator.scan(
      profileDirectory: tempDir,
      targetLanguageId: 'ja_jp',
    );

    final settings = AppSettings.defaults().copyWith(
      translation: AppSettings.defaults().translation.copyWith(
        existingTranslationPolicy: ExistingTranslationPolicy.skip,
      ),
    );

    final result = await orchestrator.translateAndPack(
      profileDirectory: tempDir,
      selectedEntries: scanResult.entries,
      targetLanguageId: 'ja_jp',
      targetLanguageDisplayName: '日本語',
      settings: settings,
      apiKey: 'test-key',
      sessionId: '20260803-120001',
    );

    expect(result.packDirectory, isNull);
    expect(result.backupDirectory, isNull);
    expect(result.translationResult.skippedModIds, ['moda']);

    final resourcePacksDir = Directory(p.join(tempDir.path, 'resourcepacks'));
    expect(await resourcePacksDir.exists(), isFalse);
  });
}
