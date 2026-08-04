import 'dart:io';

import 'package:path/path.dart' as p;

/// [files](リソースパック内の相対パス `/` 区切り → テキスト内容)を
/// `{プロファイル}/resourcepacks/{packName}/` 配下へ書き出す
/// (feature-spec.md §6.2)。
///
/// 戻り値は書き出したリソースパックのディレクトリ。
Future<Directory> writeResourcePack({
  required Directory profileDirectory,
  required String packName,
  required Map<String, String> files,
}) async {
  final packDirectory = Directory(
    p.join(profileDirectory.path, 'resourcepacks', packName),
  );
  await packDirectory.create(recursive: true);

  for (final entry in files.entries) {
    final file = File(p.joinAll([packDirectory.path, ...entry.key.split('/')]));
    await file.parent.create(recursive: true);
    await file.writeAsString(entry.value);
  }

  return packDirectory;
}
