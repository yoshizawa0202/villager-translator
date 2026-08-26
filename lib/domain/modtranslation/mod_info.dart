/// MOD 情報の取得元(feature-spec.md §6.1、優先順)。
enum ModInfoSource {
  /// `fabric.mod.json`(最優先)。
  fabricModJson,

  /// `META-INF/mods.toml`(Forgeおよび旧NeoForge)。
  forgeModsToml,

  /// `META-INF/neoforge.mods.toml`(NeoForge 1.20.5以降)。
  neoForgeModsToml,

  /// `META-INF/MANIFEST.MF`(最終手段、ID は `unknown` のためスキャン対象外)。
  manifest,
}

/// JAR から取得した MOD ID/名前/バージョン(feature-spec.md §6.1)。
class ModInfo {
  const ModInfo({
    required this.id,
    required this.name,
    required this.version,
    required this.source,
  });

  final String id;
  final String name;
  final String version;
  final ModInfoSource source;
}
