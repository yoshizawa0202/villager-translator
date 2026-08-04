import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:villager_translator/domain/common/translation_summary.dart';
import 'package:villager_translator/infrastructure/common/session_paths.dart';
import 'package:villager_translator/infrastructure/common/translation_summary_writer.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('summary_writer_test_');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('translation_summary.json をセッションディレクトリ配下へ書き出す', () async {
    const sessionId = '2026-08-04T12-00-00';
    final summary = TranslationSummary(
      sessionId: sessionId,
      targetLanguage: 'ja_jp',
      createdAt: DateTime(2026, 8, 4, 12),
      items: const [
        TranslationSummaryItem(
          type: TranslationTargetType.mod,
          id: 'example_mod',
          targetLanguage: 'ja_jp',
          success: true,
          translatedKeyCount: 3,
          totalKeyCount: 3,
        ),
      ],
    );

    final file = await const TranslationSummaryWriter().write(
      profileDirectory: tempDir,
      summary: summary,
    );

    final expectedPath = SessionPaths(
      profileDirectory: tempDir,
      sessionId: sessionId,
    ).summaryFile.path;
    expect(file.path, expectedPath);

    final restored = TranslationSummary.fromJson(
      jsonDecode(await file.readAsString()) as Map<String, dynamic>,
    );
    expect(restored.sessionId, sessionId);
    expect(restored.items.single.id, 'example_mod');
  });
}
