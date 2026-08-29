import 'dart:convert';

import '../translation/lang_codec.dart';
import 'mod_scan_entry.dart';
import 'mod_translation_service.dart';

/// `pack.mcmeta` の `pack_format`(feature-spec.md §6.2)。
const int kResourcePackFormat = 9;

/// 2つ以上のJARが同じリソースパック内パスへ出力される場合の例外。
class DuplicateModOutputPathException implements Exception {
  const DuplicateModOutputPathException({
    required this.outputPath,
    required this.jarRelativePaths,
  });

  final String outputPath;
  final List<String> jarRelativePaths;

  @override
  String toString() =>
      '同じリソースパック出力先を使う MOD が複数あります: $outputPath '
      '(${jarRelativePaths.join(', ')})';
}

String buildModLangOutputPath({
  required String modId,
  required String targetLanguageId,
  required LangFormat format,
}) => 'assets/$modId/lang/$targetLanguageId.${format.extension}';

/// API 呼び出し前に、選択したJARの出力先が一意であることを検証する。
void validateUniqueModOutputTargets({
  required Iterable<ModScanEntry> entries,
  required String targetLanguageId,
}) {
  final sourceByOutputPath = <String, String>{};

  for (final entry in entries) {
    final outputPath = buildModLangOutputPath(
      modId: entry.modInfo.id,
      targetLanguageId: targetLanguageId,
      format: entry.langFormat,
    );
    final previous = sourceByOutputPath[outputPath];
    if (previous != null) {
      throw DuplicateModOutputPathException(
        outputPath: outputPath,
        jarRelativePaths: [previous, entry.jarRelativePath],
      );
    }
    sourceByOutputPath[outputPath] = entry.jarRelativePath;
  }
}

/// `pack.mcmeta` の内容を生成する。
///
/// [packFormat] を省略した場合は現行の既定値 [kResourcePackFormat] を使う。
/// インスタンス一括翻訳のように Minecraft バージョンが分かる経路だけが判定した
/// 値を渡し、判定できない経路は従来どおりの値を維持する
/// (012-instance-batch-translation.md §11、AC-15)。
String buildPackMcmeta({
  String description = 'Villager Translator',
  int packFormat = kResourcePackFormat,
}) {
  final json = {
    'pack': {'pack_format': packFormat, 'description': description},
  };
  return const JsonEncoder.withIndent('  ').convert(json);
}

/// 翻訳結果([outputs])から、1つのリソースパックへ書き出すファイル一式
/// (相対パス → 内容)を組み立てる(feature-spec.md §6.2)。
///
/// 1回の実行で選択した全 MOD を1つのリソースパックにまとめる(MOD ごとに
/// 別パックは作らない、受け入れ条件12)。各 lang ファイルのキーは
/// [encodeLang] によりソートされる(受け入れ条件13)。
Map<String, String> buildResourcePackFiles({
  required List<ModTranslationOutput> outputs,
  required String targetLanguageId,
  String packDescription = 'Villager Translator',
  int packFormat = kResourcePackFormat,
}) {
  final files = <String, String>{
    'pack.mcmeta': buildPackMcmeta(
      description: packDescription,
      packFormat: packFormat,
    ),
  };
  final sourceByOutputPath = <String, String>{};

  for (final output in outputs) {
    final path = buildModLangOutputPath(
      modId: output.modId,
      targetLanguageId: targetLanguageId,
      format: output.format,
    );
    final previous = sourceByOutputPath[path];
    if (previous != null) {
      throw DuplicateModOutputPathException(
        outputPath: path,
        jarRelativePaths: [previous, output.jarRelativePath],
      );
    }
    sourceByOutputPath[path] = output.jarRelativePath;
    files[path] = encodeLang(output.entries, output.format);
  }

  return files;
}
