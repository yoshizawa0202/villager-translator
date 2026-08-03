import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:villager_translator/domain/llm/llm_adapter.dart';
import 'package:villager_translator/domain/llm/llm_adapter_config.dart';
import 'package:villager_translator/domain/llm/llm_provider.dart';
import 'package:villager_translator/domain/settings/app_settings.dart';
import 'package:villager_translator/domain/settings/existing_translation_policy.dart';
import 'package:villager_translator/infrastructure/llm/llm_adapter_factory.dart';
import 'package:villager_translator/infrastructure/llm/mock_llm_adapter.dart';
import 'package:villager_translator/infrastructure/patchoulitranslation/patchouli_translation_orchestrator.dart';

import '../../test_support/fake_jar_builder.dart';

class _FakeAdapterFactory implements LlmAdapterFactory {
  @override
  LlmAdapter create(LlmProvider provider, LlmAdapterConfig config) =>
      const MockLlmAdapter();
}

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
    tempDir = await Directory.systemTemp.createTemp(
      'patchouli_orchestrator_test_',
    );
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('スキャン→翻訳→JAR書き込み→バックアップまでの一連の流れが成功する(差分更新)', () async {
    final jarFile = File(p.join(tempDir.path, 'mods', 'guidemod.jar'));
    await writeFakeJar(jarFile, {
      'assets/guidemod/patchouli_books/guide/en_us/book.json':
          '{"name": "Example Guide"}',
      'assets/guidemod/patchouli_books/guide/en_us/entries/a.json':
          '{"icon": "minecraft:diamond", "name": "A", "text": "Body A"}',
      // book.json のみミラー済み(entries/a.json は未翻訳)。
      'assets/guidemod/patchouli_books/guide/ja_jp/book.json':
          '{"name": "手動修正済みガイド"}',
    });

    final beforeBytes = await jarFile.readAsBytes();

    final orchestrator = PatchouliTranslationOrchestrator(
      adapterFactory: _FakeAdapterFactory(),
    );

    final scanResult = await orchestrator.scan(
      profileDirectory: tempDir,
      targetLanguageId: 'ja_jp',
    );
    expect(scanResult.entries, hasLength(1));
    expect(scanResult.entries.single.hasExistingTranslation, isFalse);

    final settings = AppSettings.defaults().copyWith(
      translation: AppSettings.defaults().translation.copyWith(
        existingTranslationPolicy: ExistingTranslationPolicy.diffUpdate,
      ),
    );

    final result = await orchestrator.translateAndWrite(
      profileDirectory: tempDir,
      selectedEntries: scanResult.entries,
      targetLanguageId: 'ja_jp',
      targetLanguageDisplayName: '日本語',
      settings: settings,
      apiKey: 'test-key',
      sessionId: '20260803-120000',
    );

    expect(result.updatedJarRelativePaths, ['guidemod.jar']);
    expect(result.backupDirectory, isNotNull);
    expect(result.translationResult.translatedBookKeys, ['guidemod:guide']);

    final backupFile = File(
      p.join(result.backupDirectory!.path, 'guidemod.jar'),
    );
    expect(await backupFile.readAsBytes(), equals(beforeBytes));

    final contents = await _readAllText(jarFile);

    // 差分更新: 既存の book.json は変更されない。
    expect(
      contents['assets/guidemod/patchouli_books/guide/ja_jp/book.json'],
      '{"name": "手動修正済みガイド"}',
    );
    // 不足していた entries/a.json が翻訳され、icon 等の構造は維持される。
    expect(
      contents['assets/guidemod/patchouli_books/guide/ja_jp/entries/a.json'],
      '{"icon": "minecraft:diamond", "name": "[MOCK] A", "text": "[MOCK] Body A"}',
    );
    // en_us/ の原本は変更されない。
    expect(
      contents['assets/guidemod/patchouli_books/guide/en_us/book.json'],
      '{"name": "Example Guide"}',
    );
  });

  test('全対象がスキップの場合、JAR は書き込まれずバックアップも作成されない(受け入れ条件9 の裏取り)', () async {
    final jarFile = File(p.join(tempDir.path, 'mods', 'guidemod.jar'));
    await writeFakeJar(jarFile, {
      'assets/guidemod/patchouli_books/guide/en_us/book.json':
          '{"name": "Example Guide"}',
      'assets/guidemod/patchouli_books/guide/ja_jp/book.json':
          '{"name": "既存訳"}',
    });

    final beforeBytes = await jarFile.readAsBytes();

    final orchestrator = PatchouliTranslationOrchestrator(
      adapterFactory: _FakeAdapterFactory(),
    );

    final scanResult = await orchestrator.scan(
      profileDirectory: tempDir,
      targetLanguageId: 'ja_jp',
    );
    expect(scanResult.entries.single.hasExistingTranslation, isTrue);

    final settings = AppSettings.defaults().copyWith(
      translation: AppSettings.defaults().translation.copyWith(
        existingTranslationPolicy: ExistingTranslationPolicy.skip,
      ),
    );

    final result = await orchestrator.translateAndWrite(
      profileDirectory: tempDir,
      selectedEntries: scanResult.entries,
      targetLanguageId: 'ja_jp',
      targetLanguageDisplayName: '日本語',
      settings: settings,
      apiKey: 'test-key',
      sessionId: '20260803-120001',
    );

    expect(result.updatedJarRelativePaths, isEmpty);
    expect(result.backupDirectory, isNull);
    expect(result.translationResult.skippedBookKeys, ['guidemod:guide']);

    expect(await jarFile.readAsBytes(), equals(beforeBytes));

    final logsDir = Directory(p.join(tempDir.path, 'logs'));
    expect(await logsDir.exists(), isFalse);
  });
}
