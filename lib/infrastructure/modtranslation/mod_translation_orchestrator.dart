import 'dart:io';

import 'package:path/path.dart' as p;

import '../../domain/common/cancellation_token.dart';
import '../../domain/common/translation_progress.dart';
import '../../domain/common/translation_summary.dart';
import '../../domain/llm/llm_adapter_config.dart';
import '../../domain/modtranslation/jar_contents.dart';
import '../../domain/modtranslation/mod_scan_entry.dart';
import '../../domain/modtranslation/mod_translation_service.dart';
import '../../domain/modtranslation/resource_pack_builder.dart';
import '../../domain/settings/app_settings.dart';
import '../../domain/translation/chunker.dart';
import '../../domain/translation/lang_codec.dart';
import '../common/translation_summary_writer.dart';
import '../llm/llm_adapter_factory.dart';
import 'jar_reader.dart';
import 'mod_directory_scanner.dart';
import 'resource_pack_backup_writer.dart';
import 'resource_pack_writer.dart';

export '../../domain/modtranslation/mod_scan_entry.dart';
export '../../domain/modtranslation/mod_translation_service.dart';

/// 概算トークン数の既定の見積り関数(文字数を4で割った近似値)。
///
/// プロバイダーごとの厳密なトークナイザーは実装せず、チャンク分割の目安として
/// 十分な粗い近似のみを提供する(`003-translation-engine.md` の対象範囲外)。
int defaultTokenEstimator(String text) => (text.length / 4).ceil();

/// [ModTranslationOrchestrator.translateAndPack] の結果。
class ModTranslateAndPackResult {
  const ModTranslateAndPackResult({
    required this.translationResult,
    required this.packDirectory,
    required this.backupDirectory,
    required this.summary,
  });

  final ModTranslationResult translationResult;

  /// リソースパックが作成されなかった場合(全対象スキップ)は `null`
  /// (feature-spec.md §6.2、受け入れ条件11)。
  final Directory? packDirectory;
  final Directory? backupDirectory;

  /// この実行の翻訳履歴サマリ(`translation_summary.json` の内容と同一)。
  final TranslationSummary summary;
}

/// MOD スキャン・翻訳・リソースパック生成・バックアップを統括する
/// (feature-spec.md §6.1、§6.2)。
///
/// `docs/specs/003-translation-engine.md` のチャンク分割・リトライロジックと、
/// `002-settings-and-llm-adapter.md` の [LlmAdapterFactory] 境界を、
/// [translateAndPack] の中で MOD 翻訳向けに組み立てる。
class ModTranslationOrchestrator {
  ModTranslationOrchestrator({
    LlmAdapterFactory? adapterFactory,
    TokenEstimator? tokenEstimator,
  }) : _adapterFactory = adapterFactory ?? DefaultLlmAdapterFactory(),
       _tokenEstimator = tokenEstimator ?? defaultTokenEstimator;

  final LlmAdapterFactory _adapterFactory;
  final TokenEstimator _tokenEstimator;

  /// `{プロファイル}/mods/` をスキャンする(feature-spec.md §6.1)。
  Future<ModScanResult> scan({
    required Directory profileDirectory,
    required String targetLanguageId,
    void Function(ModScanSkip skip)? onSkip,
  }) {
    return scanModsDirectory(
      profileDirectory: profileDirectory,
      targetLanguageId: targetLanguageId,
      onSkip: onSkip,
    );
  }

  /// 選択された MOD を翻訳し、成果があればリソースパックを生成・バックアップする。
  ///
  /// [targetLanguageDisplayName] はプロンプトの `{language}` に渡す表示名
  /// (例: 「日本語」)、[targetLanguageId] はファイルパス・既存判定に使う
  /// 言語コード(例: `ja_jp`)。
  Future<ModTranslateAndPackResult> translateAndPack({
    required Directory profileDirectory,
    required List<ModScanEntry> selectedEntries,
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

    final translation = settings.translation;

    Future<Map<String, String>> translateChunk(Map<String, String> chunk) {
      return adapter.translate(
        content: chunk,
        targetLanguage: targetLanguageDisplayName,
        systemPrompt: settings.llm.systemPrompt,
        userPromptTemplate: settings.llm.userPrompt,
      );
    }

    List<Map<String, String>> chunkEntries(Map<String, String> entries) {
      if (translation.useTokenBasedChunking) {
        return chunkByTokenCount(
          entries,
          maxTokensPerChunk: translation.maxTokensPerChunk,
          estimateTokens: _tokenEstimator,
          fallbackToEntryBased: translation.fallbackToEntryBased,
          entryBasedChunkSize: translation.modChunkSize,
        );
      }
      return chunkByEntryCount(entries, translation.modChunkSize);
    }

    Future<Map<String, String>?> loadExistingTargetEntries(
      ModScanEntry entry,
    ) => _loadExistingTargetEntries(profileDirectory, entry, targetLanguageId);

    final translationResult = await translateSelectedMods(
      selectedEntries: selectedEntries,
      policy: translation.existingTranslationPolicy,
      loadExistingTargetEntries: loadExistingTargetEntries,
      chunkEntries: chunkEntries,
      translateChunk: translateChunk,
      maxRetries: settings.llm.maxRetries,
      cancellationToken: cancellationToken,
      onSingleFileProgress: onSingleFileProgress,
      onOverallProgress: onOverallProgress,
      onChunkResult: onChunkResult,
      onItemStarted: onItemStarted,
    );

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

    if (!translationResult.hasOutputs) {
      return ModTranslateAndPackResult(
        translationResult: translationResult,
        packDirectory: null,
        backupDirectory: null,
        summary: summary,
      );
    }

    final files = buildResourcePackFiles(
      outputs: translationResult.outputs,
      targetLanguageId: targetLanguageId,
      packDescription: translation.resourcePackName,
    );

    final packDirectory = await writeResourcePack(
      profileDirectory: profileDirectory,
      packName: translation.resourcePackName,
      files: files,
    );

    final backupDirectory = await backupResourcePack(
      profileDirectory: profileDirectory,
      packDirectory: packDirectory,
      sessionId: sessionId,
    );

    return ModTranslateAndPackResult(
      translationResult: translationResult,
      packDirectory: packDirectory,
      backupDirectory: backupDirectory,
      summary: summary,
    );
  }
}

/// 選択された MOD と処理結果を突き合わせ、翻訳履歴サマリの項目一覧を組み立てる。
///
/// キャンセルにより未着手のまま終わった MOD(outputs にも skippedModIds にも
/// 含まれないもの)はこの実行に関する結果がまだ無いため、サマリには含めない。
TranslationSummary _buildSummary({
  required String sessionId,
  required String targetLanguageId,
  required List<ModScanEntry> selectedEntries,
  required ModTranslationResult translationResult,
}) {
  final entriesById = {for (final e in selectedEntries) e.modInfo.id: e};
  final outputsById = {for (final o in translationResult.outputs) o.modId: o};

  final items = <TranslationSummaryItem>[];

  for (final modId in translationResult.translatedModIds) {
    final entry = entriesById[modId];
    final output = outputsById[modId];
    if (entry == null || output == null) continue;

    final totalKeyCount = entry.sourceEntries.length;
    final translatedKeyCount = output.entries.keys
        .where(entry.sourceEntries.containsKey)
        .length;

    items.add(
      TranslationSummaryItem(
        type: TranslationTargetType.mod,
        id: modId,
        displayName: entry.modInfo.name,
        targetLanguage: targetLanguageId,
        outputPath: entry.jarRelativePath,
        success: totalKeyCount == 0 || translatedKeyCount >= totalKeyCount,
        translatedKeyCount: translatedKeyCount,
        totalKeyCount: totalKeyCount,
      ),
    );
  }

  for (final modId in translationResult.skippedModIds) {
    final entry = entriesById[modId];
    if (entry == null) continue;

    final keyCount = entry.sourceEntries.length;
    items.add(
      TranslationSummaryItem(
        type: TranslationTargetType.mod,
        id: modId,
        displayName: entry.modInfo.name,
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

/// [entry] の対象言語ファイルが JAR 内に既に存在すれば、その内容を読み込む
/// (「既存翻訳の扱い」の翻訳直前の実チェック、feature-spec.md §4.2)。
Future<Map<String, String>?> _loadExistingTargetEntries(
  Directory profileDirectory,
  ModScanEntry entry,
  String targetLanguageId,
) async {
  final jarFile = File(
    p.join(profileDirectory.path, 'mods', entry.jarRelativePath),
  );
  if (!await jarFile.exists()) return null;

  final JarContents jarContents;
  try {
    jarContents = await readJarContents(jarFile);
  } catch (_) {
    return null;
  }

  final path =
      'assets/${entry.modInfo.id}/lang/$targetLanguageId.${entry.langFormat.extension}';
  final raw = readJarText(jarContents, path);
  if (raw == null) return null;

  try {
    return decodeLang(raw, entry.langFormat);
  } on FormatException {
    return null;
  }
}
