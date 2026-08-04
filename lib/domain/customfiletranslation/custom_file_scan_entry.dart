/// カスタムファイル(JSON/SNBT)のフォーマット(feature-spec.md §9)。
enum CustomFileFormat { json, snbt }

/// SNBT の翻訳単位に使う固定キー(feature-spec.md §9: ファイル全体を1つの
/// 翻訳単位として送信する)。
const String kCustomSnbtContentKey = 'content';

/// スキャン対象一覧に含まれるカスタムファイル1件分の情報(feature-spec.md §9)。
class CustomFileScanEntry {
  const CustomFileScanEntry({
    required this.format,
    required this.absolutePath,
    required this.relativePath,
    required this.sourceEntries,
    this.jsonRoot,
  });

  final CustomFileFormat format;

  /// 実ファイルシステム上の絶対パス(出力先ディレクトリの解決に使う)。
  final String absolutePath;

  /// 選択したルートディレクトリからの相対パス(`/` 区切り、表示用)。
  final String relativePath;

  /// 翻訳対象のキー→値。
  /// JSON: ネストした構造をフラット化したドット/ブラケット記法のキー→
  /// 文字列の葉ノード([CustomFileFormat.json])。
  /// SNBT: [kCustomSnbtContentKey] → ファイル全文([CustomFileFormat.snbt])。
  final Map<String, String> sourceEntries;

  /// `jsonDecode` によるパース済み構造(再構成に使う、[CustomFileFormat.json] のみ)。
  final dynamic jsonRoot;
}
