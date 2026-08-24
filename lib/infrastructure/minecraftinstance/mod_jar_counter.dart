import 'dart:io';

import 'package:path/path.dart' as p;

/// `{rootPath}/mods/*.jar` のファイル数だけを数える
/// (011-launcher-instance-discovery.md §13)。
///
/// JAR の中身は開かない。翻訳可能 MOD 件数は自動解析(§16)で確定する。
/// 読み取れない場合は 0 を返し、例外を呼び出し元へ伝播させない。
Future<int> countModJarFiles(Directory rootDirectory) async {
  final modsDirectory = Directory(p.join(rootDirectory.path, 'mods'));
  try {
    if (!await modsDirectory.exists()) return 0;
    return await modsDirectory
        .list(followLinks: false)
        .where(
          (entity) =>
              entity is File &&
              p.extension(entity.path).toLowerCase() == '.jar',
        )
        .length;
  } catch (_) {
    return 0;
  }
}
