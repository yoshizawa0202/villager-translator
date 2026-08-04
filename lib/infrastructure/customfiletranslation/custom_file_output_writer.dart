import 'dart:io';

import 'package:path/path.dart' as p;

import '../../domain/customfiletranslation/custom_file_output_builder.dart';

/// [files] を [outputDirectory] 配下へ書き出す(feature-spec.md §9)。
///
/// 出力先ディレクトリが存在しなければ作成する。原本のファイルは変更しない。
Future<List<File>> writeCustomFileOutputFiles({
  required Directory outputDirectory,
  required List<CustomFileOutputFile> files,
}) async {
  await outputDirectory.create(recursive: true);

  final written = <File>[];
  for (final file in files) {
    final target = File(p.join(outputDirectory.path, file.fileName));
    await target.writeAsString(file.content);
    written.add(target);
  }
  return written;
}
