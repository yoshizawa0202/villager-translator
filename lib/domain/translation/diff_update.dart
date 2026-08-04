/// 差分更新ロジック(feature-spec.md §5.5)。
///
/// MOD・Better Quests(標準/直接)・FTB Quests(KubeJS lang)・Patchouli
/// ガイドブックの、キー単位で構造化されたフォーマットに共通利用できる
/// 汎用ロジックとして実装する(SNBT 直接編集は対象外)。
/// 「既存翻訳の扱い」(スキップ/差分更新/全て再翻訳)の分岐そのものは
/// 各機能仕様(`004`〜`007`)側の責務であり、本ファイルは差分更新モードが
/// 選択された場合に使う不足キー抽出・マージ処理のみを提供する。
library;

/// 差分更新のために解決した翻訳ジョブ。
class DiffUpdateJob {
  const DiffUpdateJob({
    required this.existingEntries,
    required this.keysToTranslate,
  });

  /// 対象言語ファイルに既に存在する内容(存在しなければ空の Map)。
  final Map<String, String> existingEntries;

  /// 翻訳が必要な不足キーのみを含む Map(原文の値)。
  final Map<String, String> keysToTranslate;

  /// 不足キーが1件もなく、翻訳ジョブ自体を作成する必要がないかどうか。
  bool get isSkipped => keysToTranslate.isEmpty;
}

/// 翻訳元 [sourceEntries] のキー集合から、対象言語ファイルに既に存在する
/// キー([existingTargetEntries])を除外し、不足分のみを翻訳対象とする
/// ジョブを解決する。
///
/// [existingTargetEntries] が `null`(対象言語ファイルが存在しない)の場合は、
/// 通常の全件翻訳と同じ扱いとして全キーが対象になる。
DiffUpdateJob resolveDiffUpdateJob({
  required Map<String, String> sourceEntries,
  required Map<String, String>? existingTargetEntries,
}) {
  final existing = existingTargetEntries ?? const {};

  final keysToTranslate = <String, String>{};
  for (final entry in sourceEntries.entries) {
    if (!existing.containsKey(entry.key)) {
      keysToTranslate[entry.key] = entry.value;
    }
  }

  return DiffUpdateJob(
    existingEntries: existing,
    keysToTranslate: keysToTranslate,
  );
}

/// 既存の対象言語ファイルの内容([existingEntries])と、新たに翻訳した
/// 不足キー([newlyTranslatedEntries])をマージして書き出す内容を作る。
///
/// 既存キーの値は上書きしない(ユーザーによる手動修正の保護、
/// feature-spec.md §5.5)。
Map<String, String> mergeDiffUpdateResult({
  required Map<String, String> existingEntries,
  required Map<String, String> newlyTranslatedEntries,
}) {
  final merged = <String, String>{...existingEntries};
  for (final entry in newlyTranslatedEntries.entries) {
    merged.putIfAbsent(entry.key, () => entry.value);
  }
  return merged;
}
