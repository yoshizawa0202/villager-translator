/// Minecraft インスタンス判定に使うマーカー(011-launcher-instance-discovery.md §10)。
///
/// 対象ディレクトリ直下に存在するかどうかだけを見る。実ファイルシステムへの
/// アクセス(マーカー集合の収集)は infrastructure 層が担当し、ここは純粋関数に
/// とどめる。
const List<String> kInstanceMarkers = [
  'mods',
  'config',
  'resourcepacks',
  'saves',
  'options.txt',
  'logs',
];

/// インスタンスと判定するために必要なマーカーの最小一致数(§10)。
///
/// 単一のマーカーで判定すると MOD 配布用の作業フォルダを誤検出し、全マーカーを
/// 必須にすると `saves/` がまだ無い新規インスタンスを取りこぼすため 2 とする。
const int kMinimumInstanceMarkerMatches = 2;

/// [presentNames](対象ディレクトリ直下に存在するファイル・ディレクトリ名)から
/// 一致したマーカー数を数える。比較は大文字小文字を区別しない(Windows)。
int countInstanceMarkers(Iterable<String> presentNames) {
  final present = presentNames.map((e) => e.toLowerCase()).toSet();
  return kInstanceMarkers.where(present.contains).length;
}

/// マーカー判定(§10)。ランチャー固有メタデータが読み取れない場合に使う。
bool looksLikeMinecraftInstance(Iterable<String> presentNames) =>
    countInstanceMarkers(presentNames) >= kMinimumInstanceMarkerMatches;

/// ランチャールート判定に使うマーカー(§15.1)。
///
/// 手動追加パス直下にこれらのいずれかがあれば、対応する Detector の
/// ランチャールート候補として扱う。
const List<String> kLauncherRootMarkers = [
  'instances',
  'profiles',
  'prismlauncher.cfg',
];

/// [presentNames] がランチャールートの特徴を持つかどうか(§15.1)。
bool looksLikeLauncherRoot(Iterable<String> presentNames) {
  final present = presentNames.map((e) => e.toLowerCase()).toSet();
  return kLauncherRootMarkers.any(present.contains);
}
