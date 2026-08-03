import 'dart:io';

import 'package:path/path.dart' as p;

import '../../domain/questtranslation/quest_scan_entry.dart';

/// 翻訳前に選択した SNBT ファイルを、セッションディレクトリ配下の
/// `logs/localizer/{sessionId}/backup/snbt_original/` へバックアップする
/// (feature-spec.md §7.1、受け入れ条件6)。
///
/// SNBT は同一ファイルへ直接上書きするため、翻訳失敗時にも原本相当を
/// バックアップから復元できるよう、翻訳を開始する前に呼び出す。
/// プロファイルディレクトリからの相対パス構造をバックアップ先でも維持する
/// (同名ファイルが別チャプターに存在する場合の衝突を避けるため)。
Future<Directory> backupSnbtOriginals({
  required Directory profileDirectory,
  required List<QuestScanEntry> entries,
  required String sessionId,
}) async {
  final backupDirectory = Directory(
    p.join(
      profileDirectory.path,
      'logs',
      'localizer',
      sessionId,
      'backup',
      'snbt_original',
    ),
  );
  await backupDirectory.create(recursive: true);

  for (final entry in entries) {
    assert(entry.format == QuestFormat.ftbQuestsSnbt);

    final segments = entry.relativePath.split('/');
    final source = File(p.joinAll([profileDirectory.path, ...segments]));
    final target = File(p.joinAll([backupDirectory.path, ...segments]));
    await target.parent.create(recursive: true);
    await source.copy(target.path);
  }

  return backupDirectory;
}
