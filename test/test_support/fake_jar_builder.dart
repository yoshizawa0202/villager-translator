import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';

/// テスト用に、[entries](パス → テキスト内容)を持つ `.jar`(zip)ファイルを
/// [targetFile] に書き出す。
Future<void> writeFakeJar(File targetFile, Map<String, String> entries) async {
  final archive = Archive();
  for (final entry in entries.entries) {
    final bytes = utf8.encode(entry.value);
    archive.addFile(ArchiveFile.noCompress(entry.key, bytes.length, bytes));
  }

  final zipBytes = ZipEncoder().encodeBytes(archive);
  await targetFile.parent.create(recursive: true);
  await targetFile.writeAsBytes(zipBytes);
}
