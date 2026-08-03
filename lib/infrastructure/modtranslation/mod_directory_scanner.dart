import 'dart:io';

import 'package:path/path.dart' as p;

import '../../domain/modtranslation/mod_scan_entry.dart';
import '../../domain/modtranslation/mod_scanner.dart';
import 'jar_reader.dart';

/// `{プロファイル}/mods/` 直下(非再帰)の `.jar` をスキャンする(feature-spec.md §6.1)。
///
/// [onSkip] はスキップ理由をログへ記録するためのフック(`008` でログ機能と
/// 統合する前提の最小限のコールバック)。
Future<ModScanResult> scanModsDirectory({
  required Directory profileDirectory,
  required String targetLanguageId,
  void Function(ModScanSkip skip)? onSkip,
}) async {
  final modsDirectory = Directory(p.join(profileDirectory.path, 'mods'));
  if (!await modsDirectory.exists()) {
    return const ModScanResult(entries: [], skips: []);
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

  final entries = <ModScanEntry>[];
  final skips = <ModScanSkip>[];

  for (final jarFile in jarFiles) {
    final relativePath = p.basename(jarFile.path);
    ModScanSkip? skip;
    try {
      final jarContents = await readJarContents(jarFile);
      final outcome = scanModJar(
        jarRelativePath: relativePath,
        jar: jarContents,
        targetLanguageId: targetLanguageId,
      );
      if (outcome.entry != null) {
        entries.add(outcome.entry!);
      } else {
        skip = outcome.skip;
      }
    } catch (e) {
      skip = ModScanSkip(
        jarRelativePath: relativePath,
        reason: ModScanSkipReason.corruptJar,
        detail: e.toString(),
      );
    }

    if (skip != null) {
      skips.add(skip);
      onSkip?.call(skip);
    }
  }

  return ModScanResult(entries: entries, skips: skips);
}
