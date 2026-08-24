/// 検出対象の Minecraft ランチャー種別(011-launcher-instance-discovery.md §1)。
///
/// [manual] は自動検出ではなく、利用者が手動で追加したパスから登録された
/// インスタンスを表す(§15.1)。
enum MinecraftLauncher {
  official('Minecraft', 'Minecraft Launcher'),
  prism('Prism', 'Prism Launcher'),
  curseForge('CurseForge', 'CurseForge'),
  atLauncher('ATLauncher', 'ATLauncher'),
  modrinth('Modrinth', 'Modrinth App'),
  manual('手動追加', '手動追加');

  const MinecraftLauncher(this.filterLabel, this.displayName);

  /// 一覧画面のランチャー別フィルターに表示する短い名称(§14)。
  final String filterLabel;

  /// 一覧画面のランチャー見出しに表示する名称(§13)。
  final String displayName;
}
