import 'dart:io';

import 'package:archive/archive.dart';

/// [jarFile] へ、[newEntries](JAR 内パス `/` 区切り → テキスト内容)を
/// 追記・上書きする(feature-spec.md §8.2)。
///
/// コピー→全エントリを転送→新規エントリ追加→原本を置き換える、という
/// アトミックな差し替え手順で行う(受け入れ条件8)。[newEntries] に含まれない
/// 既存エントリは、元の圧縮データをそのまま(再圧縮せず)引き継ぐため、
/// 内容だけでなく圧縮率も維持される。
///
/// 一時ファイルへ書き出してから [jarFile] と同じディレクトリ内で `rename`
/// することで、書き込み処理の途中で例外が発生しても原本の JAR が破損した
/// 状態で残らないようにする(`rename` は同一ボリューム内であれば OS レベルで
/// アトミックに行われ、成功するまで原本は一切変更されない、受け入れ条件10)。
///
/// Windows では宛先が既に存在すると `rename` が失敗するため、既存 JAR を
/// 一旦 `.bak` へ退避してからリネームし、成功後にバックアップを削除する
/// (`SettingsRepository.save()` と同様の手順)。
Future<void> writePatchouliTranslationsToJar({
  required File jarFile,
  required Map<String, String> newEntries,
}) async {
  final originalBytes = await jarFile.readAsBytes();
  final archive = ZipDecoder().decodeBytes(originalBytes);

  final outputArchive = Archive();
  for (final file in archive.files) {
    if (file.isFile && newEntries.containsKey(file.name)) {
      continue; // 後段でまとめて上書きする。
    }
    outputArchive.addFile(file);
  }
  for (final entry in newEntries.entries) {
    outputArchive.addFile(ArchiveFile.string(entry.key, entry.value));
  }

  final zipBytes = ZipEncoder().encodeBytes(outputArchive);

  final tempFile = File('${jarFile.path}.tmp');
  final backupFile = File('${jarFile.path}.bak');
  await tempFile.writeAsBytes(zipBytes);

  if (await backupFile.exists()) {
    await backupFile.delete();
  }
  if (await jarFile.exists()) {
    await jarFile.rename(backupFile.path);
  }
  await tempFile.rename(jarFile.path);
  if (await backupFile.exists()) {
    await backupFile.delete();
  }
}
