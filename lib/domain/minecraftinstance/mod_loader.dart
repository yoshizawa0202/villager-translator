/// インスタンスの Mod Loader 種別(011-launcher-instance-discovery.md §1)。
///
/// 判定できない場合は [unknown] とし、検出自体は成功させる(AC-12)。
enum ModLoader {
  vanilla('Vanilla'),
  forge('Forge'),
  neoForge('NeoForge'),
  fabric('Fabric'),
  quilt('Quilt'),
  unknown('Unknown');

  const ModLoader(this.displayName);

  /// UI に表示する名称。
  final String displayName;

  /// ランチャーメタデータ中の Loader 名(`forge`、`neoforge` など)から解決する。
  /// 未知の値・`null` は [unknown] を返す(例外を投げない)。
  static ModLoader fromName(String? name) {
    final normalized = name?.trim().toLowerCase().replaceAll('-', '');
    switch (normalized) {
      case 'vanilla':
      case 'none':
        return ModLoader.vanilla;
      case 'forge':
      case 'minecraftforge':
        return ModLoader.forge;
      case 'neoforge':
      case 'neoforged':
        return ModLoader.neoForge;
      case 'fabric':
      case 'fabricloader':
        return ModLoader.fabric;
      case 'quilt':
      case 'quiltloader':
        return ModLoader.quilt;
      default:
        return ModLoader.unknown;
    }
  }
}
