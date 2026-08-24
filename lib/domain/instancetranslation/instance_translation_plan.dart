import '../llm/llm_provider.dart';
import '../minecraftinstance/minecraft_instance.dart';
import '../modtranslation/mod_scan_entry.dart';
import '../patchoulitranslation/patchouli_book_entry.dart';
import '../questtranslation/quest_scan_entry.dart';
import 'instance_translation_mode.dart';

/// インスタンス一括翻訳 1 回分を表す計画
/// (012-instance-batch-translation.md §2)。
///
/// 対象一覧には既存のスキャン結果の型をそのまま持たせる。既存オーケストレーターの
/// `selectedEntries` へ無変換で渡すためであり、これらを包む新しい対象モデルは
/// 追加しない(設計判断「対象モデルに既存のスキャン結果型をそのまま持たせる」)。
///
/// これにより「1 Minecraft インスタンス = 1 翻訳ジョブ」が成立する。
class InstanceTranslationPlan {
  const InstanceTranslationPlan({
    required this.instance,
    required this.targetLanguageId,
    required this.targetLanguageDisplayName,
    required this.translateMods,
    required this.translateQuests,
    required this.translateGuidebooks,
    required this.mods,
    required this.quests,
    required this.guidebooks,
    required this.mode,
    required this.provider,
    required this.model,
  });

  final MinecraftInstance instance;

  final String targetLanguageId;
  final String targetLanguageDisplayName;

  final bool translateMods;
  final bool translateQuests;
  final bool translateGuidebooks;

  final List<ModScanEntry> mods;
  final List<QuestScanEntry> quests;
  final List<PatchouliBookEntry> guidebooks;

  final InstanceTranslationMode mode;

  final LlmProvider provider;
  final String model;

  /// 実際に処理する MOD(カテゴリが OFF なら空)。
  List<ModScanEntry> get effectiveMods => translateMods ? mods : const [];

  /// 実際に処理するクエスト(カテゴリが OFF なら空)。
  List<QuestScanEntry> get effectiveQuests =>
      translateQuests ? quests : const [];

  /// 実際に処理するガイドブック(カテゴリが OFF なら空)。
  List<PatchouliBookEntry> get effectiveGuidebooks =>
      translateGuidebooks ? guidebooks : const [];

  /// 1 件でも翻訳対象があるか(全カテゴリ OFF のとき実行させない、AC-02)。
  bool get hasAnyTarget =>
      effectiveMods.isNotEmpty ||
      effectiveQuests.isNotEmpty ||
      effectiveGuidebooks.isNotEmpty;

  InstanceTranslationPlan copyWith({
    bool? translateMods,
    bool? translateQuests,
    bool? translateGuidebooks,
    List<ModScanEntry>? mods,
    List<QuestScanEntry>? quests,
    List<PatchouliBookEntry>? guidebooks,
    InstanceTranslationMode? mode,
    String? targetLanguageId,
    String? targetLanguageDisplayName,
    LlmProvider? provider,
    String? model,
  }) {
    return InstanceTranslationPlan(
      instance: instance,
      targetLanguageId: targetLanguageId ?? this.targetLanguageId,
      targetLanguageDisplayName:
          targetLanguageDisplayName ?? this.targetLanguageDisplayName,
      translateMods: translateMods ?? this.translateMods,
      translateQuests: translateQuests ?? this.translateQuests,
      translateGuidebooks: translateGuidebooks ?? this.translateGuidebooks,
      mods: mods ?? this.mods,
      quests: quests ?? this.quests,
      guidebooks: guidebooks ?? this.guidebooks,
      mode: mode ?? this.mode,
      provider: provider ?? this.provider,
      model: model ?? this.model,
    );
  }
}
