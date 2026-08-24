import 'dart:io';

import 'package:path/path.dart' as p;

/// テスト用に「Minecraft インスタンスらしい」フォルダを作る
/// (011-launcher-instance-discovery.md §10 のマーカーを 2 つ以上満たす)。
Future<Directory> createInstanceMarkers(String path) async {
  final directory = Directory(path);
  await Directory(p.join(path, 'mods')).create(recursive: true);
  await Directory(p.join(path, 'config')).create(recursive: true);
  return directory;
}

/// テキストファイルを(親ディレクトリごと)書き出す。
Future<File> writeTextFile(String path, String content) async {
  final file = File(path);
  await file.parent.create(recursive: true);
  await file.writeAsString(content);
  return file;
}
