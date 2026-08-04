import 'dart:io';

import 'package:path/path.dart' as p;

import '../../domain/questtranslation/quest_output_builder.dart';

/// [files](プロファイルディレクトリからの相対パス `/` 区切り → 内容)を
/// 実際のファイルとして書き出す(feature-spec.md §7.1、§7.2)。
///
/// SNBT の場合は [QuestOutputFile.relativePath] が元ファイルと同一パスに
/// なるため、結果として直接上書きになる(受け入れ条件5)。JSON/LANG の場合は
/// 常に新規パス(隣接する言語サフィックス付きファイル)になるため、原本は
/// 変更されない(受け入れ条件7、受け入れ条件8)。
Future<List<File>> writeQuestOutputFiles({
  required Directory profileDirectory,
  required List<QuestOutputFile> files,
}) async {
  final written = <File>[];
  for (final file in files) {
    final target = File(
      p.joinAll([profileDirectory.path, ...file.relativePath.split('/')]),
    );
    await target.parent.create(recursive: true);
    await target.writeAsString(file.content);
    written.add(target);
  }
  return written;
}
