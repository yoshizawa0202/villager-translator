import 'package:villager_translator/domain/instancetranslation/instance_translation_mode.dart';
import 'package:villager_translator/domain/instancetranslation/instance_translation_plan.dart';
import 'package:villager_translator/domain/llm/llm_provider.dart';
import 'package:villager_translator/domain/minecraftinstance/minecraft_instance.dart';
import 'package:villager_translator/domain/minecraftinstance/minecraft_launcher.dart';
import 'package:villager_translator/domain/modtranslation/mod_info.dart';
import 'package:villager_translator/domain/modtranslation/mod_scan_entry.dart';
import 'package:villager_translator/domain/patchoulitranslation/patchouli_book_entry.dart';
import 'package:villager_translator/domain/questtranslation/quest_scan_entry.dart';
import 'package:villager_translator/domain/translation/lang_codec.dart';

/// 一括翻訳のテストで使う固定のスキャン結果(012 §2)。
ModScanEntry buildModEntry({
  required String id,
  String? jarRelativePath,
  Map<String, String> sourceEntries = const {'item.a': 'Item A'},
  bool hasExistingTranslation = false,
}) => ModScanEntry(
  modInfo: ModInfo(
    id: id,
    name: id,
    version: '1.0',
    source: ModInfoSource.fabricModJson,
  ),
  jarRelativePath: jarRelativePath ?? '$id.jar',
  langFormat: LangFormat.json,
  sourceLangPath: 'assets/$id/lang/en_us.json',
  sourceEntries: sourceEntries,
  hasExistingTranslation: hasExistingTranslation,
);

QuestScanEntry buildQuestEntry({
  required String relativePath,
  Map<String, String> sourceEntries = const {'q.1': 'Quest 1'},
}) => QuestScanEntry(
  format: QuestFormat.ftbQuestsKubejsLang,
  relativePath: relativePath,
  sourceEntries: sourceEntries,
);

PatchouliBookEntry buildBookEntry({
  required String modId,
  required String bookId,
  Map<String, String> sourceEntries = const {'entries/a.json#0': 'Page'},
  bool hasExistingTranslation = false,
}) => PatchouliBookEntry(
  modId: modId,
  bookId: bookId,
  jarRelativePath: '$modId.jar',
  files: const [],
  sourceEntries: sourceEntries,
  hasExistingTranslation: hasExistingTranslation,
);

MinecraftInstance buildTestInstance({
  required String rootPath,
  String? minecraftVersion = '1.20.1',
}) => MinecraftInstance(
  id: 'test-instance',
  name: 'Prominence II',
  launcher: MinecraftLauncher.prism,
  rootPath: rootPath,
  minecraftVersion: minecraftVersion,
);

InstanceTranslationPlan buildTestPlan({
  required String rootPath,
  String? minecraftVersion = '1.20.1',
  List<ModScanEntry> mods = const [],
  List<QuestScanEntry> quests = const [],
  List<PatchouliBookEntry> guidebooks = const [],
  bool translateMods = true,
  bool translateQuests = true,
  bool translateGuidebooks = true,
  InstanceTranslationMode mode = InstanceTranslationMode.diffUpdate,
  LlmProvider provider = LlmProvider.openai,
  String model = 'gpt-5.6-luna',
}) => InstanceTranslationPlan(
  instance: buildTestInstance(
    rootPath: rootPath,
    minecraftVersion: minecraftVersion,
  ),
  targetLanguageId: 'ja_jp',
  targetLanguageDisplayName: '日本語',
  translateMods: translateMods,
  translateQuests: translateQuests,
  translateGuidebooks: translateGuidebooks,
  mods: mods,
  quests: quests,
  guidebooks: guidebooks,
  mode: mode,
  provider: provider,
  model: model,
);
