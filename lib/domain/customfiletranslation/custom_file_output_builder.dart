import 'dart:convert';

import 'package:path/path.dart' as p;

import 'custom_file_scan_entry.dart';
import 'custom_file_translation_service.dart';
import 'json_flattener.dart';

/// `translated/` 配下へ書き出す出力ファイル1件(ファイル名と内容)。
class CustomFileOutputFile {
  const CustomFileOutputFile({required this.fileName, required this.content});

  final String fileName;
  final String content;
}

/// [outputs] から `translated/` 配下へ書き出すファイル一式を組み立てる
/// (feature-spec.md §9、受け入れ条件7)。
///
/// - JSON: [CustomFileScanEntry.jsonRoot] の構造・型・キー順序を保ったまま、
///   翻訳結果の文字列のみを差し替えて再構成する(受け入れ条件5)。
/// - SNBT: 翻訳結果のファイル全文をそのまま書き出す。
///
/// 出力ファイル名は `{targetLanguage}_{ファイル名}` を基本形とし、[outputs] を
/// [CustomFileScanEntry.relativePath] の昇順で決定論的に処理する。異なる
/// サブディレクトリの同名ファイルを選択した場合など、出力ファイル名が衝突する
/// 場合は2件目以降に拡張子の前の連番(`_2` `_3` ...)を付与して一意化し、
/// 上書きによるデータ消失を避ける(受け入れ条件8、移行上の判断)。
List<CustomFileOutputFile> buildCustomFileOutputFiles(
  List<CustomFileTranslationOutput> outputs,
  String targetLanguageId,
) {
  final ordered = outputs.toList()
    ..sort((a, b) => a.entry.relativePath.compareTo(b.entry.relativePath));

  final usedNames = <String>{};
  final files = <CustomFileOutputFile>[];

  for (final output in ordered) {
    final content = _buildContent(output);
    final baseName =
        '${targetLanguageId}_${p.basename(output.entry.relativePath)}';
    final fileName = _resolveUniqueFileName(baseName, usedNames);
    usedNames.add(fileName);
    files.add(CustomFileOutputFile(fileName: fileName, content: content));
  }

  return files;
}

String _buildContent(CustomFileTranslationOutput output) {
  final entry = output.entry;
  switch (entry.format) {
    case CustomFileFormat.json:
      final rebuilt = rebuildJsonWithTranslations(
        entry.jsonRoot,
        output.entries,
      );
      return const JsonEncoder.withIndent('  ').convert(rebuilt);
    case CustomFileFormat.snbt:
      return output.entries[kCustomSnbtContentKey] ??
          entry.sourceEntries[kCustomSnbtContentKey] ??
          '';
  }
}

String _resolveUniqueFileName(String baseName, Set<String> usedNames) {
  if (!usedNames.contains(baseName)) return baseName;

  final ext = p.extension(baseName);
  final stem = baseName.substring(0, baseName.length - ext.length);
  var counter = 2;
  while (usedNames.contains('${stem}_$counter$ext')) {
    counter++;
  }
  return '${stem}_$counter$ext';
}
