import '../modtranslation/mod_scan_entry.dart';
import '../patchoulitranslation/patchouli_book_entry.dart';
import '../questtranslation/quest_scan_entry.dart';
import 'minecraft_instance.dart';

/// クエストの表示上のまとまり(011-launcher-instance-discovery.md §16)。
///
/// 画面ではクエスト形式を「FTB Quests」「Better Quests」の 2 系統で提示するため、
/// [QuestFormat] の 4 値をこの 2 値へ写像する。
enum QuestFamily {
  ftbQuests('FTB Quests'),
  betterQuesting('Better Quests');

  const QuestFamily(this.displayName);

  final String displayName;

  static QuestFamily of(QuestFormat format) {
    switch (format) {
      case QuestFormat.ftbQuestsKubejsLang:
      case QuestFormat.ftbQuestsSnbt:
        return QuestFamily.ftbQuests;
      case QuestFormat.betterQuestingStandard:
      case QuestFormat.betterQuestingDirect:
        return QuestFamily.betterQuesting;
    }
  }
}

/// クエスト 1 系統分の検出状況(§16)。
class QuestFamilySummary {
  const QuestFamilySummary({
    required this.family,
    required this.fileCount,
    required this.stringCount,
  });

  final QuestFamily family;

  /// 検出したクエストファイル数。
  final int fileCount;

  /// 翻訳対象文字列数([QuestScanEntry.sourceEntries] の合計)。
  final int stringCount;

  bool get detected => fileCount > 0;
}

/// インスタンス選択後の自動解析結果(§16)。
///
/// 既存の 3 スキャナの結果をそのまま保持し、表示用の内訳だけを導出する。
/// 新しいスキャン処理・新しい翻訳済み判定ロジックは追加しない。
class InstanceAnalysis {
  const InstanceAnalysis({
    required this.instance,
    required this.modJarCount,
    required this.mods,
    required this.quests,
    required this.guidebooks,
  });

  /// 解析対象(メタデータ多段フォールバックの第3段で補完済みの場合がある、§12)。
  final MinecraftInstance instance;

  /// `{rootPath}/mods/*.jar` のファイル数(JAR の中身は開かずに数えた値、§13)。
  final int modJarCount;

  /// 翻訳可能な MOD(`en_us` lang ファイルを持つもの)。
  final List<ModScanEntry> mods;

  final List<QuestScanEntry> quests;
  final List<PatchouliBookEntry> guidebooks;

  /// 翻訳可能 MOD 件数(§16)。
  int get translatableModCount => mods.length;

  /// 翻訳済み MOD 件数([ModScanEntry.hasExistingTranslation] から集計)。
  int get translatedModCount =>
      mods.where((e) => e.hasExistingTranslation).length;

  /// 未翻訳 MOD 件数。
  int get untranslatedModCount => translatableModCount - translatedModCount;

  /// 翻訳済みガイドブック件数([PatchouliBookEntry.hasExistingTranslation])。
  int get translatedGuidebookCount =>
      guidebooks.where((e) => e.hasExistingTranslation).length;

  /// 未翻訳ガイドブック件数。
  int get untranslatedGuidebookCount =>
      guidebooks.length - translatedGuidebookCount;

  /// クエスト形式別の検出状況(未検出の系統も件数 0 で必ず含む、§16)。
  List<QuestFamilySummary> get questSummaries {
    return [
      for (final family in QuestFamily.values)
        () {
          final matching = quests
              .where((e) => QuestFamily.of(e.format) == family)
              .toList();
          return QuestFamilySummary(
            family: family,
            fileCount: matching.length,
            stringCount: matching.fold(
              0,
              (sum, e) => sum + e.sourceEntries.length,
            ),
          );
        }(),
    ];
  }

  /// 翻訳対象が 1 件も無いかどうか(一括翻訳の実行可否判定に使う)。
  bool get isEmpty => mods.isEmpty && quests.isEmpty && guidebooks.isEmpty;
}
