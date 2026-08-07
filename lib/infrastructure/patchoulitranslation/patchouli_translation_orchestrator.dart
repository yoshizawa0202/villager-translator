import 'dart:io';

import 'package:path/path.dart' as p;

import '../../domain/common/cancellation_token.dart';
import '../../domain/common/translation_progress.dart';
import '../../domain/common/translation_summary.dart';
import '../../domain/llm/llm_adapter_config.dart';
import '../../domain/modtranslation/jar_contents.dart';
import '../../domain/patchoulitranslation/patchouli_book_entry.dart';
import '../../domain/patchoulitranslation/patchouli_output_builder.dart';
import '../../domain/patchoulitranslation/patchouli_string_extractor.dart';
import '../../domain/patchoulitranslation/patchouli_translation_service.dart';
import '../../domain/settings/app_settings.dart';
import '../common/translation_summary_writer.dart';
import '../llm/llm_adapter_factory.dart';
import '../modtranslation/jar_reader.dart';
import 'patchouli_backup_writer.dart';
import 'patchouli_directory_scanner.dart';
import 'patchouli_jar_writer.dart';

export '../../domain/patchoulitranslation/patchouli_book_entry.dart';
export '../../domain/patchoulitranslation/patchouli_translation_service.dart';

/// [PatchouliTranslationOrchestrator.translateAndWrite] の結果。
class PatchouliTranslateAndWriteResult {
  const PatchouliTranslateAndWriteResult({
    required this.translationResult,
    required this.updatedJarRelativePaths,
    required this.backupDirectory,
    required this.summary,
  });

  final PatchouliTranslationResult translationResult;

  /// 実際に書き込みが行われた JAR(`mods/` からの相対パス)の一覧。
  final List<String> updatedJarRelativePaths;

  /// JAR が1件も書き込まれなかった場合(全対象スキップ)は `null`。
  final Directory? backupDirectory;

  /// この実行の翻訳履歴サマリ(`translation_summary.json` の内容と同一)。
  final TranslationSummary summary;
}

/// Patchouli ガイドブックのスキャン・翻訳・JAR 書き込み・バックアップを統括する
/// (feature-spec.md §8)。
class PatchouliTranslationOrchestrator {
  PatchouliTranslationOrchestrator({LlmAdapterFactory? adapterFactory})
    : _adapterFactory = adapterFactory ?? DefaultLlmAdapterFactory();

  final LlmAdapterFactory _adapterFactory;

  /// `{プロファイル}/mods/` をスキャンする(feature-spec.md §8.1)。
  Future<PatchouliScanResult> scan({
    required Directory profileDirectory,
    required String targetLanguageId,
    void Function(PatchouliScanSkip skip)? onSkip,
  }) {
    return scanPatchouliBooksDirectory(
      profileDirectory: profileDirectory,
      targetLanguageId: targetLanguageId,
      onSkip: onSkip,
    );
  }

  /// 選択された本を翻訳し、対応する JAR へ書き込む。
  ///
  /// 実際に書き込みが発生する JAR について、書き込みを開始する前に必ず
  /// バックアップする(feature-spec.md §8.2、受け入れ条件9)。
  Future<PatchouliTranslateAndWriteResult> translateAndWrite({
    required Directory profileDirectory,
    required List<PatchouliBookEntry> selectedEntries,
    required String targetLanguageId,
    required String targetLanguageDisplayName,
    required AppSettings settings,
    required String apiKey,
    required String sessionId,
    CancellationToken? cancellationToken,
    SingleFileProgressCallback? onSingleFileProgress,
    OverallProgressCallback? onOverallProgress,
    ItemChunkResultCallback? onChunkResult,
    CurrentItemCallback? onItemStarted,
  }) async {
    final adapter = _adapterFactory.create(
      settings.llm.provider,
      LlmAdapterConfig(
        apiKey: apiKey,
        model: settings.llm.effectiveModel,
        temperature: settings.llm.temperature,
        maxRetries: settings.llm.maxRetries,
      ),
    );

    Future<Map<String, String>> translateChunk(Map<String, String> chunk) {
      return adapter.translate(
        content: chunk,
        targetLanguage: targetLanguageDisplayName,
        systemPrompt: settings.llm.systemPrompt,
        userPromptTemplate: settings.llm.userPrompt,
      );
    }

    Future<PatchouliExistingTranslation> loadExistingTargetEntries(
      PatchouliBookEntry entry,
    ) => _loadExistingPatchouliEntries(
      profileDirectory,
      entry,
      targetLanguageId,
    );

    final translationResult = await translatePatchouliBooks(
      selectedEntries: selectedEntries,
      policy: settings.translation.existingTranslationPolicy,
      loadExistingTargetEntries: loadExistingTargetEntries,
      translateChunk: translateChunk,
      maxRetries: settings.llm.maxRetries,
      cancellationToken: cancellationToken,
      onSingleFileProgress: onSingleFileProgress,
      onOverallProgress: onOverallProgress,
      onChunkResult: onChunkResult,
      onItemStarted: onItemStarted,
    );

    // JAR ごとに新規エントリをまとめる(同一 JAR に複数の本が含まれる場合に、
    // 1つの JAR に対して書き込みを1回にまとめるため)。
    final entriesByJar = <String, Map<String, String>>{};
    for (final output in translationResult.outputs) {
      final jarEntries = entriesByJar.putIfAbsent(
        output.entry.jarRelativePath,
        () => {},
      );
      for (final file in buildPatchouliJarOutputEntries(
        output,
        targetLanguageId,
      )) {
        jarEntries[file.jarPath] = file.content;
      }
    }

    final summary = _buildSummary(
      sessionId: sessionId,
      targetLanguageId: targetLanguageId,
      selectedEntries: selectedEntries,
      translationResult: translationResult,
    );
    await const TranslationSummaryWriter().write(
      profileDirectory: profileDirectory,
      summary: summary,
    );

    if (entriesByJar.isEmpty) {
      return PatchouliTranslateAndWriteResult(
        translationResult: translationResult,
        updatedJarRelativePaths: const [],
        backupDirectory: null,
        summary: summary,
      );
    }

    final backupDirectory = await backupPatchouliJars(
      profileDirectory: profileDirectory,
      jarRelativePaths: entriesByJar.keys,
      sessionId: sessionId,
    );

    for (final jarRelativePath in entriesByJar.keys) {
      final jarFile = File(
        p.join(profileDirectory.path, 'mods', jarRelativePath),
      );
      await writePatchouliTranslationsToJar(
        jarFile: jarFile,
        newEntries: entriesByJar[jarRelativePath]!,
      );
    }

    return PatchouliTranslateAndWriteResult(
      translationResult: translationResult,
      updatedJarRelativePaths: entriesByJar.keys.toList()..sort(),
      backupDirectory: backupDirectory,
      summary: summary,
    );
  }
}

/// 選択された本と処理結果を突き合わせ、翻訳履歴サマリの項目一覧を組み立てる。
/// キャンセルにより未着手のまま終わった本はサマリに含めない。
TranslationSummary _buildSummary({
  required String sessionId,
  required String targetLanguageId,
  required List<PatchouliBookEntry> selectedEntries,
  required PatchouliTranslationResult translationResult,
}) {
  final entriesByKey = {for (final e in selectedEntries) e.bookKey: e};
  final outputsByKey = {
    for (final o in translationResult.outputs) o.entry.bookKey: o,
  };

  final items = <TranslationSummaryItem>[];

  for (final bookKey in translationResult.translatedBookKeys) {
    final entry = entriesByKey[bookKey];
    final output = outputsByKey[bookKey];
    if (entry == null || output == null) continue;

    final totalKeyCount = entry.sourceEntries.length;
    final translatedKeyCount = output.entries.keys
        .where(entry.sourceEntries.containsKey)
        .length;

    items.add(
      TranslationSummaryItem(
        type: TranslationTargetType.patchouli,
        id: bookKey,
        displayName: bookKey,
        targetLanguage: targetLanguageId,
        outputPath: entry.jarRelativePath,
        success: totalKeyCount == 0 || translatedKeyCount >= totalKeyCount,
        translatedKeyCount: translatedKeyCount,
        totalKeyCount: totalKeyCount,
      ),
    );
  }

  for (final bookKey in translationResult.skippedBookKeys) {
    final entry = entriesByKey[bookKey];
    if (entry == null) continue;

    final keyCount = entry.sourceEntries.length;
    items.add(
      TranslationSummaryItem(
        type: TranslationTargetType.patchouli,
        id: bookKey,
        displayName: bookKey,
        targetLanguage: targetLanguageId,
        outputPath: null,
        success: true,
        translatedKeyCount: keyCount,
        totalKeyCount: keyCount,
      ),
    );
  }

  return TranslationSummary(
    sessionId: sessionId,
    targetLanguage: targetLanguageId,
    createdAt: DateTime.now(),
    items: items,
  );
}

/// [entry] の対象言語ミラーファイル群を実際に JAR から読み込む
/// (「既存翻訳の扱い」の翻訳直前の実チェック、feature-spec.md §8.1)。
Future<PatchouliExistingTranslation> _loadExistingPatchouliEntries(
  Directory profileDirectory,
  PatchouliBookEntry entry,
  String targetLanguageId,
) async {
  final jarFile = File(
    p.join(profileDirectory.path, 'mods', entry.jarRelativePath),
  );
  if (!await jarFile.exists()) {
    return const PatchouliExistingTranslation(isComplete: false, entries: {});
  }

  final JarContents jarContents;
  try {
    jarContents = await readJarContents(jarFile);
  } catch (_) {
    return const PatchouliExistingTranslation(isComplete: false, entries: {});
  }

  final existingEntries = <String, String>{};
  var isComplete = true;

  for (final file in entry.files) {
    final mirrorPath =
        'assets/${entry.modId}/patchouli_books/${entry.bookId}/'
        '$targetLanguageId/${file.relativePath}';
    final raw = _readTextCaseInsensitive(jarContents, mirrorPath);
    if (raw == null) {
      isComplete = false;
      continue;
    }

    final unit = buildPatchouliFileTranslationUnit(raw);
    for (final e in unit.entries.entries) {
      existingEntries['${file.relativePath}#${e.key}'] = e.value;
    }
  }

  return PatchouliExistingTranslation(
    isComplete: isComplete,
    entries: existingEntries,
  );
}

String? _readTextCaseInsensitive(JarContents jar, String path) {
  final lowerPath = path.toLowerCase();
  for (final key in jar.keys) {
    if (key.toLowerCase() == lowerPath) {
      return readJarText(jar, key);
    }
  }
  return null;
}
