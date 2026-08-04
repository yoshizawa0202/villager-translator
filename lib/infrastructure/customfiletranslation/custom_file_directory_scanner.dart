import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../domain/customfiletranslation/custom_file_scan_entry.dart';
import '../../domain/customfiletranslation/json_flattener.dart';

/// 出力先として使う `translated/` ディレクトリ名(feature-spec.md §9)。
const String kCustomFileOutputDirName = 'translated';

/// [rootDirectory] 配下の `.json` `.snbt` を再帰的にスキャンする
/// (feature-spec.md §9、受け入れ条件1)。
///
/// 前回実行の出力ファイルを翻訳元として再検出しないよう、
/// [kCustomFileOutputDirName] 配下は除外する(移行上の判断)。壊れたファイルが
/// 1件あってもスキャン全体は継続する。翻訳対象の文字列が1件もないファイル
/// (JSON: 文字列の葉ノードなし、SNBT: 到達不能)は一覧に含めない。
Future<List<CustomFileScanEntry>> scanCustomFilesDirectory({
  required Directory rootDirectory,
}) async {
  final files =
      await rootDirectory
            .list(recursive: true)
            .where((e) => e is File)
            .cast<File>()
            .where((f) => !_isUnderOutputDir(f, rootDirectory))
            .where((f) {
              final ext = p.extension(f.path).toLowerCase();
              return ext == '.json' || ext == '.snbt';
            })
            .toList()
        ..sort((a, b) => a.path.compareTo(b.path));

  final entries = <CustomFileScanEntry>[];
  for (final file in files) {
    final relativePath = p
        .relative(file.path, from: rootDirectory.path)
        .split(Platform.pathSeparator)
        .join('/');
    final ext = p.extension(file.path).toLowerCase();

    try {
      if (ext == '.json') {
        final content = await file.readAsString();
        final root = jsonDecode(content);
        final sourceEntries = flattenJsonStrings(root);
        if (sourceEntries.isEmpty) continue;
        entries.add(
          CustomFileScanEntry(
            format: CustomFileFormat.json,
            absolutePath: file.path,
            relativePath: relativePath,
            sourceEntries: sourceEntries,
            jsonRoot: root,
          ),
        );
      } else {
        final content = await file.readAsString();
        entries.add(
          CustomFileScanEntry(
            format: CustomFileFormat.snbt,
            absolutePath: file.path,
            relativePath: relativePath,
            sourceEntries: {kCustomSnbtContentKey: content},
          ),
        );
      }
    } catch (_) {
      // 壊れたファイルはスキップし、他のファイルのスキャンを継続する。
    }
  }
  return entries;
}

bool _isUnderOutputDir(File file, Directory rootDirectory) {
  final relative = p.relative(file.path, from: rootDirectory.path);
  final segments = relative.split(Platform.pathSeparator);
  return segments.contains(kCustomFileOutputDirName);
}
