import 'dart:io';

import 'package:path/path.dart' as p;

/// 翻訳前に選択した JAR ファイルを、セッションディレクトリ配下の
/// `logs/localizer/{sessionId}/backup/patchouli_jar/` へバックアップする
/// (feature-spec.md §8.2、受け入れ条件9)。
///
/// JAR へ直接書き込む(追記)前に必ず呼び出す。MOD 翻訳と異なり Patchouli は
/// JAR 自体を書き換えるため、`AGENTS.md` の「元データ保全」制約に従い
/// バックアップを必須とする(旧実装からの意図的な改善、`006` 移行上の判断)。
/// [jarRelativePaths] は重複していても構わない(内部で重複排除する)。
Future<Directory> backupPatchouliJars({
  required Directory profileDirectory,
  required Iterable<String> jarRelativePaths,
  required String sessionId,
}) async {
  final backupDirectory = Directory(
    p.join(
      profileDirectory.path,
      'logs',
      'localizer',
      sessionId,
      'backup',
      'patchouli_jar',
    ),
  );
  await backupDirectory.create(recursive: true);

  for (final relativePath in jarRelativePaths.toSet()) {
    final source = File(p.join(profileDirectory.path, 'mods', relativePath));
    final target = File(p.join(backupDirectory.path, relativePath));
    await target.parent.create(recursive: true);
    await source.copy(target.path);
  }

  return backupDirectory;
}
