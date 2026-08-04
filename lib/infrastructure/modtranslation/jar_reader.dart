import 'dart:io';

import 'package:archive/archive.dart';

import '../../domain/modtranslation/jar_contents.dart';

/// [jarFile](`.jar` = zip)を展開し、[JarContents](パス → バイト列)へ変換する。
///
/// JAR 自体が破損していて zip として開けない場合は [ArchiveException] などを
/// そのまま投げる。呼び出し側([ModDirectoryScanner])が MOD 単位で捕捉し、
/// スキャン全体を継続する(feature-spec.md §6.1、受け入れ条件5)。
Future<JarContents> readJarContents(File jarFile) async {
  final bytes = await jarFile.readAsBytes();
  final archive = ZipDecoder().decodeBytes(bytes);

  final contents = <String, List<int>>{};
  for (final file in archive.files) {
    if (!file.isFile) continue;
    contents[file.name] = file.content;
  }
  return contents;
}
