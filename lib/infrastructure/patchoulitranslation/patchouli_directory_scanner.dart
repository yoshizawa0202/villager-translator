import 'dart:io';

import 'package:path/path.dart' as p;

import '../../domain/patchoulitranslation/patchouli_book_entry.dart';
import '../../domain/patchoulitranslation/patchouli_scanner.dart';
import '../modtranslation/jar_reader.dart';

/// `{プロファイル}/mods/` 直下(非再帰)の `.jar` から Patchouli ガイドブックを
/// スキャンする(feature-spec.md §8.1)。MOD スキャン(`004-mod-translation.md`)
/// と同じ `.jar` 一覧を使う。
///
/// [onSkip] はスキップ理由をログへ記録するためのフック(`008` でログ機能と
/// 統合する前提の最小限のコールバック)。
Future<PatchouliScanResult> scanPatchouliBooksDirectory({
  required Directory profileDirectory,
  required String targetLanguageId,
  void Function(PatchouliScanSkip skip)? onSkip,
}) async {
  final modsDirectory = Directory(p.join(profileDirectory.path, 'mods'));
  if (!await modsDirectory.exists()) {
    return const PatchouliScanResult(entries: [], skips: []);
  }

  final jarFiles = await modsDirectory
      .list()
      .where(
        (entity) =>
            entity is File && p.extension(entity.path).toLowerCase() == '.jar',
      )
      .cast<File>()
      .toList();
  jarFiles.sort((a, b) => p.basename(a.path).compareTo(p.basename(b.path)));

  final entries = <PatchouliBookEntry>[];
  final skips = <PatchouliScanSkip>[];

  for (final jarFile in jarFiles) {
    final relativePath = p.basename(jarFile.path);
    try {
      final jarContents = await readJarContents(jarFile);
      entries.addAll(
        scanPatchouliBooksInJar(
          jarRelativePath: relativePath,
          jar: jarContents,
          targetLanguageId: targetLanguageId,
        ),
      );
    } catch (e) {
      final skip = PatchouliScanSkip(
        jarRelativePath: relativePath,
        reason: PatchouliScanSkipReason.corruptJar,
        detail: e.toString(),
      );
      skips.add(skip);
      onSkip?.call(skip);
    }
  }

  return PatchouliScanResult(
    entries: sortPatchouliBookEntries(entries),
    skips: skips,
  );
}
