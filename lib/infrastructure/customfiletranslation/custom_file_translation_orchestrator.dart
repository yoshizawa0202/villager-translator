import 'dart:io';

import 'package:path/path.dart' as p;

import '../../domain/customfiletranslation/custom_file_output_builder.dart';
import '../../domain/customfiletranslation/custom_file_scan_entry.dart';
import '../../domain/customfiletranslation/custom_file_translation_service.dart';
import '../../domain/llm/llm_adapter_config.dart';
import '../../domain/settings/app_settings.dart';
import '../llm/llm_adapter_factory.dart';
import 'custom_file_directory_scanner.dart';
import 'custom_file_output_writer.dart';

export '../../domain/customfiletranslation/custom_file_scan_entry.dart';
export '../../domain/customfiletranslation/custom_file_translation_service.dart';

/// [CustomFileTranslationOrchestrator.translateAndWrite] の結果。
class CustomFileTranslateAndWriteResult {
  const CustomFileTranslateAndWriteResult({
    required this.translationResult,
    required this.outputDirectory,
    required this.writtenFiles,
  });

  final CustomFileTranslationResult translationResult;

  /// `translated/` の出力先(翻訳結果が1件もない場合は `null`)。
  final Directory? outputDirectory;
  final List<File> writtenFiles;
}

/// カスタムファイル(JSON/SNBT)のスキャン・翻訳・出力を統括する
/// (feature-spec.md §9)。
///
/// MOD/クエスト/Patchouli のような特定フォーマットの知識に依存しない、
/// フォールバック的な翻訳経路として位置づけられるため、「既存翻訳の扱い」設定
/// やバックアップは持たない(原本を変更しない出力方式のため、feature-spec.md §12)。
class CustomFileTranslationOrchestrator {
  CustomFileTranslationOrchestrator({LlmAdapterFactory? adapterFactory})
    : _adapterFactory = adapterFactory ?? DefaultLlmAdapterFactory();

  final LlmAdapterFactory _adapterFactory;

  /// [rootDirectory] 配下の `.json` `.snbt` を再帰的にスキャンする。
  Future<List<CustomFileScanEntry>> scan({required Directory rootDirectory}) {
    return scanCustomFilesDirectory(rootDirectory: rootDirectory);
  }

  /// 選択されたカスタムファイルを翻訳し、`translated/` 配下へ書き出す。
  ///
  /// 出力先は選択した対象ファイルを相対パス昇順で並べたときの最初のファイルの
  /// ディレクトリ配下の `translated/` とする(feature-spec.md §9、受け入れ条件7、
  /// 移行上の判断)。
  Future<CustomFileTranslateAndWriteResult> translateAndWrite({
    required List<CustomFileScanEntry> selectedEntries,
    required String targetLanguageId,
    required String targetLanguageDisplayName,
    required AppSettings settings,
    required String apiKey,
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

    final translationResult = await translateCustomFileEntries(
      selectedEntries: selectedEntries,
      translateChunk: translateChunk,
      maxRetries: settings.llm.maxRetries,
    );

    if (translationResult.outputs.isEmpty) {
      return CustomFileTranslateAndWriteResult(
        translationResult: translationResult,
        outputDirectory: null,
        writtenFiles: const [],
      );
    }

    final files = buildCustomFileOutputFiles(
      translationResult.outputs,
      targetLanguageId,
    );

    final orderedSelection = selectedEntries.toList()
      ..sort((a, b) => a.relativePath.compareTo(b.relativePath));
    final firstEntry = orderedSelection.first;
    final outputDirectory = Directory(
      p.join(p.dirname(firstEntry.absolutePath), kCustomFileOutputDirName),
    );

    final writtenFiles = await writeCustomFileOutputFiles(
      outputDirectory: outputDirectory,
      files: files,
    );

    return CustomFileTranslateAndWriteResult(
      translationResult: translationResult,
      outputDirectory: outputDirectory,
      writtenFiles: writtenFiles,
    );
  }
}
