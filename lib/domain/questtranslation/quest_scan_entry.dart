import 'snbt_extractor.dart';

/// クエストファイルの形式(feature-spec.md §7.1、§7.2)。
enum QuestFormat {
  /// FTB Quests(KubeJS 経由)、`en_us.json` 等の JSON。
  ftbQuestsKubejsLang,

  /// FTB Quests(SNBT 直接編集)。
  ftbQuestsSnbt,

  /// Better Quests 標準形式(`resources/betterquesting/lang/*.json`)。
  betterQuestingStandard,

  /// Better Quests 直接形式(`config/betterquesting/DefaultQuests.lang`)。
  betterQuestingDirect,
}

/// スキャン対象一覧に含まれるクエストファイル1件分の情報(feature-spec.md §7)。
class QuestScanEntry {
  const QuestScanEntry({
    required this.format,
    required this.relativePath,
    required this.sourceEntries,
    this.snbtOriginalContent,
    this.snbtSpans,
  });

  final QuestFormat format;

  /// プロファイルディレクトリからの相対パス(`/` 区切り、表示用・出力先解決用)。
  final String relativePath;

  /// 翻訳対象のキー→値(JSON/LANG)、または抽出順の連番キー→値(SNBT)。
  final Map<String, String> sourceEntries;

  /// SNBT の元の全文(再構成に必要、[QuestFormat.ftbQuestsSnbt] のみ)。
  final String? snbtOriginalContent;

  /// SNBT の抽出スパン一覧([sourceEntries] と同じ並び順、[QuestFormat.ftbQuestsSnbt] のみ)。
  final List<SnbtStringSpan>? snbtSpans;
}
