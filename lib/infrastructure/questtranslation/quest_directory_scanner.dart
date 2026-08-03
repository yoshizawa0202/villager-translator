import 'dart:io';

import 'package:path/path.dart' as p;

import '../../domain/questtranslation/quest_lang_scan.dart';
import '../../domain/questtranslation/quest_scan_entry.dart';
import '../../domain/questtranslation/snbt_extractor.dart';
import '../../domain/translation/lang_codec.dart';

/// FTB Quests(KubeJS lang / SNBT)の優先順位付き候補ディレクトリ
/// (feature-spec.md §7.1)。
const List<String> kFtbQuestsSnbtCandidateDirs = [
  'config/ftbquests/quests',
  'config/ftbquests/normal',
  'config/ftbquests',
];

/// `{プロファイル}` 配下の FTB Quests / Better Quests をスキャンする
/// (feature-spec.md §7.1、§7.2)。
///
/// 壊れたファイルが1件あってもスキャン全体は継続する(他機能仕様と同様の方針)。
Future<List<QuestScanEntry>> scanQuestsDirectory({
  required Directory profileDirectory,
}) async {
  final entries = <QuestScanEntry>[];

  entries.addAll(await _scanFtbQuests(profileDirectory));
  entries.addAll(await _scanBetterQuestingStandard(profileDirectory));

  final direct = await _scanBetterQuestingDirect(profileDirectory);
  if (direct != null) entries.add(direct);

  return entries;
}

Future<List<QuestScanEntry>> _scanFtbQuests(Directory profileDirectory) async {
  final kubejsLangDir = Directory(
    p.join(profileDirectory.path, 'kubejs', 'assets', 'kubejs', 'lang'),
  );
  final kubejsEnUs = File(p.join(kubejsLangDir.path, 'en_us.json'));

  if (await kubejsEnUs.exists()) {
    return _scanKubejsLangDir(profileDirectory, kubejsLangDir);
  }

  return _scanSnbtDirectory(profileDirectory);
}

Future<List<QuestScanEntry>> _scanKubejsLangDir(
  Directory profileDirectory,
  Directory kubejsLangDir,
) async {
  final basenames = await kubejsLangDir
      .list()
      .where((e) => e is File)
      .map((e) => p.basename(e.path))
      .toList();
  final candidates = listCandidateLangJsonBasenames(basenames);

  final entries = <QuestScanEntry>[];
  for (final name in candidates) {
    final file = File(p.join(kubejsLangDir.path, name));
    try {
      final decoded = decodeLangJson(await file.readAsString());
      entries.add(
        QuestScanEntry(
          format: QuestFormat.ftbQuestsKubejsLang,
          relativePath: 'kubejs/assets/kubejs/lang/$name',
          sourceEntries: decoded,
        ),
      );
    } catch (_) {
      // 壊れたファイルはスキップし、他のファイルのスキャンを継続する。
    }
  }
  return entries;
}

Future<List<QuestScanEntry>> _scanSnbtDirectory(
  Directory profileDirectory,
) async {
  Directory? root;
  for (final candidate in kFtbQuestsSnbtCandidateDirs) {
    final dir = Directory(
      p.joinAll([profileDirectory.path, ...candidate.split('/')]),
    );
    if (await dir.exists()) {
      root = dir;
      break;
    }
  }
  if (root == null) return const [];

  final snbtFiles =
      await root
          .list(recursive: true)
          .where(
            (e) => e is File && p.extension(e.path).toLowerCase() == '.snbt',
          )
          .cast<File>()
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));

  final entries = <QuestScanEntry>[];
  for (final file in snbtFiles) {
    try {
      final content = await file.readAsString();
      final unit = buildSnbtTranslationUnit(content);
      if (unit.entries.isEmpty) continue;

      final relativePath = p
          .relative(file.path, from: profileDirectory.path)
          .split(Platform.pathSeparator)
          .join('/');

      entries.add(
        QuestScanEntry(
          format: QuestFormat.ftbQuestsSnbt,
          relativePath: relativePath,
          sourceEntries: unit.entries,
          snbtOriginalContent: unit.originalContent,
          snbtSpans: unit.spans,
        ),
      );
    } catch (_) {
      // 壊れたファイルはスキップし、他のファイルのスキャンを継続する。
    }
  }
  return entries;
}

Future<List<QuestScanEntry>> _scanBetterQuestingStandard(
  Directory profileDirectory,
) async {
  final dir = Directory(
    p.join(profileDirectory.path, 'resources', 'betterquesting', 'lang'),
  );
  if (!await dir.exists()) return const [];

  final basenames = await dir
      .list()
      .where((e) => e is File)
      .map((e) => p.basename(e.path))
      .toList();
  final candidates = listCandidateLangJsonBasenames(basenames);

  final entries = <QuestScanEntry>[];
  for (final name in candidates) {
    final file = File(p.join(dir.path, name));
    try {
      final decoded = decodeLangJson(await file.readAsString());
      entries.add(
        QuestScanEntry(
          format: QuestFormat.betterQuestingStandard,
          relativePath: 'resources/betterquesting/lang/$name',
          sourceEntries: decoded,
        ),
      );
    } catch (_) {
      // 壊れたファイルはスキップし、他のファイルのスキャンを継続する。
    }
  }
  return entries;
}

Future<QuestScanEntry?> _scanBetterQuestingDirect(
  Directory profileDirectory,
) async {
  final file = File(
    p.join(profileDirectory.path, 'config', 'betterquesting', 'DefaultQuests.lang'),
  );
  if (!await file.exists()) return null;

  try {
    final decoded = decodeLangFile(await file.readAsString());
    return QuestScanEntry(
      format: QuestFormat.betterQuestingDirect,
      relativePath: 'config/betterquesting/DefaultQuests.lang',
      sourceEntries: decoded,
    );
  } catch (_) {
    return null;
  }
}
