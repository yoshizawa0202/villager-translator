import '../translation/retry_policy.dart';

/// 単一ファイル(単一対象)内のチャンク進捗(0〜100%、feature-spec.md §10)。
class ChunkProgress {
  const ChunkProgress({
    required this.completedChunks,
    required this.totalChunks,
  });

  final int completedChunks;
  final int totalChunks;

  /// 0.0〜1.0 の進捗率(総チャンク数が0の場合は1.0)。
  double get fraction => totalChunks == 0 ? 1.0 : completedChunks / totalChunks;

  int get percent => (fraction * 100).round();
}

/// バッチ全体(選択された対象群)の進捗(完了件数/総件数、feature-spec.md §10)。
class OverallProgress {
  const OverallProgress({
    required this.completedItems,
    required this.totalItems,
  });

  final int completedItems;
  final int totalItems;

  int get percent =>
      totalItems == 0 ? 100 : ((completedItems / totalItems) * 100).round();

  /// 「X / Y 件完了 (Z%)」形式のテキスト表示(feature-spec.md §10)。
  String get label => '$completedItems / $totalItems 件完了 ($percent%)';
}

/// 単一ファイル進捗の通知コールバック。
typedef SingleFileProgressCallback = void Function(ChunkProgress progress);

/// 全体進捗の通知コールバック。
typedef OverallProgressCallback = void Function(OverallProgress progress);

/// [itemDisplayName](MOD 名やファイルの相対パスなど、処理対象の表示名)に
/// 対するチャンク単位の処理結果([ChunkResult])を通知するコールバック。
/// 粒度の細かいデバッグログ(1翻訳単位の実行内容・結果)に使う。
typedef ItemChunkResultCallback =
    void Function(String itemDisplayName, ChunkResult result);
