import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:villager_translator/domain/llm/llm_adapter.dart';
import 'package:villager_translator/domain/llm/llm_adapter_config.dart';
import 'package:villager_translator/domain/llm/llm_provider.dart';
import 'package:villager_translator/domain/settings/app_settings.dart';
import 'package:villager_translator/infrastructure/customfiletranslation/custom_file_translation_orchestrator.dart';
import 'package:villager_translator/infrastructure/llm/llm_adapter_factory.dart';
import 'package:villager_translator/infrastructure/llm/mock_llm_adapter.dart';

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
    tempDir = await Directory.systemTemp.createTemp(
      'custom_file_orchestrator_test_',
    );
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test(
    '複数ファイルを選択して翻訳すると、最初の対象ファイルのディレクトリ配下の '
    'translated/ に {targetLanguage}_{ファイル名} として出力され、原本は変更されない(受け入れ条件7)',
    () async {
      final fileA = File(p.join(tempDir.path, 'dirA', 'a.json'));
      await _writeFile(fileA.path, '{"title": "Hello"}');
      final fileB = File(p.join(tempDir.path, 'dirB', 'b.snbt'));
      await _writeFile(fileB.path, 'raw content');

      final bytesBeforeA = await fileA.readAsBytes();
      final bytesBeforeB = await fileB.readAsBytes();

      final orchestrator = CustomFileTranslationOrchestrator(
        adapterFactory: _FakeAdapterFactory(),
      );
      final scanned = await orchestrator.scan(rootDirectory: tempDir);
      expect(scanned, hasLength(2));

      final result = await orchestrator.translateAndWrite(
        profileDirectory: tempDir,
        selectedEntries: scanned,
        targetLanguageId: 'ja_jp',
        targetLanguageDisplayName: '日本語',
        settings: AppSettings.defaults(),
        apiKey: 'test-key',
        sessionId: '2026-08-04T12-00-00',
      );

      expect(result.translationResult.translatedPaths, [
        'dirA/a.json',
        'dirB/b.snbt',
      ]);
      // 受け入れ条件12: 翻訳履歴サマリが実行のたびに生成される。
      expect(result.summary.sessionId, '2026-08-04T12-00-00');
      expect(result.summary.items.length, 2);
      expect(result.summary.items.every((i) => i.success), isTrue);
      // 相対パス昇順で最初のファイル(dirA/a.json)のディレクトリ配下に出力される。
      expect(
        result.outputDirectory!.path,
        p.join(tempDir.path, 'dirA', 'translated'),
      );

      final jsonOutput = File(
        p.join(result.outputDirectory!.path, 'ja_jp_a.json'),
      );
      final snbtOutput = File(
        p.join(result.outputDirectory!.path, 'ja_jp_b.snbt'),
      );

      expect(jsonDecode(await jsonOutput.readAsString()), {
        'title': '[MOCK] Hello',
      });
      expect(await snbtOutput.readAsString(), '[MOCK] raw content');

      // 原本は変更されない。
      expect(await fileA.readAsBytes(), equals(bytesBeforeA));
      expect(await fileB.readAsBytes(), equals(bytesBeforeB));
    },
  );

  test('翻訳結果が1件もない場合は出力ディレクトリを作成しない', () async {
    final orchestrator = CustomFileTranslationOrchestrator(
      adapterFactory: _FakeAdapterFactory(),
    );

    final result = await orchestrator.translateAndWrite(
      profileDirectory: tempDir,
      selectedEntries: const [],
      targetLanguageId: 'ja_jp',
      targetLanguageDisplayName: '日本語',
      settings: AppSettings.defaults(),
      apiKey: 'test-key',
      sessionId: '2026-08-04T12-00-00',
    );

    expect(result.outputDirectory, isNull);
    expect(result.writtenFiles, isEmpty);
  });
}
