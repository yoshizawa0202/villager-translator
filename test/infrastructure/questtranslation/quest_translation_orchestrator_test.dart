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
import 'package:villager_translator/infrastructure/questtranslation/quest_translation_orchestrator.dart';

class _FakeAdapterFactory implements LlmAdapterFactory {
  @override
  LlmAdapter create(LlmProvider provider, LlmAdapterConfig config) =>
      const MockLlmAdapter();
}

Future<void> _writeFile(String path, String content) async {
  final file = File(path);
  await file.parent.create(recursive: true);
  await file.writeAsString(content);
}

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('quest_orchestrator_test_');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('KubeJS lang の翻訳結果が kubejs と ftbquests の両方に書き込まれる(受け入れ条件2)', () async {
    await _writeFile(
      p.join(tempDir.path, 'kubejs', 'assets', 'kubejs', 'lang', 'en_us.json'),
      '{"quest.a": "Quest A"}',
    );

    final orchestrator = QuestTranslationOrchestrator(
      adapterFactory: _FakeAdapterFactory(),
    );
    final scanned = await orchestrator.scan(profileDirectory: tempDir);
    expect(scanned, hasLength(1));

    final result = await orchestrator.translateAndWrite(
      profileDirectory: tempDir,
      selectedEntries: scanned,
      targetLanguageId: 'ja_jp',
      targetLanguageDisplayName: '日本語',
      settings: AppSettings.defaults(),
      apiKey: 'test-key',
      sessionId: '20260803-120000',
    );

    expect(result.translationResult.translatedPaths, [
      'kubejs/assets/kubejs/lang/en_us.json',
    ]);
    // 受け入れ条件12: 翻訳履歴サマリが実行のたびに生成される。
    expect(result.summary.sessionId, '20260803-120000');
    expect(result.summary.items.single.success, isTrue);

    final kubejsContent = await File(
      p.joinAll([
        tempDir.path,
        'kubejs',
        'assets',
        'kubejs',
        'lang',
        'ja_jp.json',
      ]),
    ).readAsString();
    final ftbquestsContent = await File(
      p.joinAll([
        tempDir.path,
        'kubejs',
        'assets',
        'ftbquests',
        'lang',
        'ja_jp.json',
      ]),
    ).readAsString();

    expect(kubejsContent, contains('[MOCK] Quest A'));
    expect(kubejsContent, ftbquestsContent);
  });

  test('SNBT は翻訳前にバックアップされたうえで同一ファイルへ上書きされる(受け入れ条件5,6)', () async {
    final snbtFile = File(
      p.join(tempDir.path, 'config', 'ftbquests', 'quests', 'chapter1.snbt'),
    );
    await snbtFile.parent.create(recursive: true);
    await snbtFile.writeAsString('title: "Chapter One"');

    final orchestrator = QuestTranslationOrchestrator(
      adapterFactory: _FakeAdapterFactory(),
    );
    final scanned = await orchestrator.scan(profileDirectory: tempDir);
    expect(scanned, hasLength(1));

    final result = await orchestrator.translateAndWrite(
      profileDirectory: tempDir,
      selectedEntries: scanned,
      targetLanguageId: 'ja_jp',
      targetLanguageDisplayName: '日本語',
      settings: AppSettings.defaults(),
      apiKey: 'test-key',
      sessionId: '20260803-120001',
    );

    expect(result.snbtBackupDirectory, isNotNull);
    final backupFile = File(
      p.joinAll([
        result.snbtBackupDirectory!.path,
        'config',
        'ftbquests',
        'quests',
        'chapter1.snbt',
      ]),
    );
    expect(await backupFile.readAsString(), 'title: "Chapter One"');

    // 原本は同一ファイルへ上書きされ、言語サフィックス付きの別ファイルは作られない。
    expect(await snbtFile.readAsString(), contains('[MOCK] Chapter One'));
    expect(
      await Directory(
        p.join(tempDir.path, 'config', 'ftbquests', 'quests'),
      ).list().length,
      1,
    );
  });

  test('Better Quests 標準・直接は新規ファイルとして出力され、原本は変更されない(受け入れ条件7,8)', () async {
    final standardFile = File(
      p.join(tempDir.path, 'resources', 'betterquesting', 'lang', 'en_us.json'),
    );
    await standardFile.parent.create(recursive: true);
    await standardFile.writeAsString('{"quest.b": "Quest B"}');

    final directFile = File(
      p.join(tempDir.path, 'config', 'betterquesting', 'DefaultQuests.lang'),
    );
    await directFile.parent.create(recursive: true);
    await directFile.writeAsString('quest.c=Quest C');

    final standardBytesBefore = await standardFile.readAsBytes();
    final directBytesBefore = await directFile.readAsBytes();

    final orchestrator = QuestTranslationOrchestrator(
      adapterFactory: _FakeAdapterFactory(),
    );
    final scanned = await orchestrator.scan(profileDirectory: tempDir);
    expect(scanned, hasLength(2));

    await orchestrator.translateAndWrite(
      profileDirectory: tempDir,
      selectedEntries: scanned,
      targetLanguageId: 'ja_jp',
      targetLanguageDisplayName: '日本語',
      settings: AppSettings.defaults().copyWith(
        translation: AppSettings.defaults().translation.copyWith(
          existingTranslationPolicy: ExistingTranslationPolicy.retranslateAll,
        ),
      ),
      apiKey: 'test-key',
      sessionId: '20260803-120002',
    );

    final standardOutput = File(
      p.joinAll([
        tempDir.path,
        'resources',
        'betterquesting',
        'lang',
        'en_us.ja_jp.json',
      ]),
    );
    final directOutput = File(
      p.joinAll([
        tempDir.path,
        'config',
        'betterquesting',
        'DefaultQuests.ja_jp.lang',
      ]),
    );

    expect(await standardOutput.readAsString(), contains('[MOCK] Quest B'));
    expect(await directOutput.readAsString(), 'quest.c=[MOCK] Quest C');

    expect(await standardFile.readAsBytes(), equals(standardBytesBefore));
    expect(await directFile.readAsBytes(), equals(directBytesBefore));
  });
}
