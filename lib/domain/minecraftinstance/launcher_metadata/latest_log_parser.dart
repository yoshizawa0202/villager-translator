import 'dart:convert';

import '../mod_loader.dart';
import 'instance_metadata.dart';

/// `{rootPath}/logs/latest.log` の起動時ログ行から Minecraft バージョンおよび
/// Loader を抽出する(011-launcher-instance-discovery.md §12 の第2段)。
///
/// ログ形式は Loader・バージョンによって揺れるため(本仕様の「要検証項目」)、
/// 代表的な形式を順に照合し、いずれにも一致しない場合は
/// [InstanceMetadata.empty] を返す。例外は投げない。
InstanceMetadata parseLatestLog(String content) {
  String? minecraftVersion;
  var modLoader = ModLoader.unknown;
  String? modLoaderVersion;

  for (final rawLine in const LineSplitter().convert(content)) {
    final line = rawLine.trim();
    if (line.isEmpty) continue;

    // Fabric / Quilt: `Loading Minecraft 1.21.1 with Fabric Loader 0.16.9`
    final fabricLike = _fabricLoading.firstMatch(line);
    if (fabricLike != null) {
      minecraftVersion ??= fabricLike.group(1);
      if (modLoader == ModLoader.unknown) {
        modLoader = ModLoader.fromName(fabricLike.group(2));
        modLoaderVersion ??= fabricLike.group(3);
      }
      continue;
    }

    // Forge / NeoForge(FML の起動引数): `--fml.mcVersion, 1.20.1`
    final mcVersion = _fmlMcVersion.firstMatch(line);
    if (mcVersion != null) minecraftVersion ??= mcVersion.group(1);

    final forgeVersion = _fmlForgeVersion.firstMatch(line);
    if (forgeVersion != null && modLoader == ModLoader.unknown) {
      modLoader = ModLoader.fromName(forgeVersion.group(1));
      modLoaderVersion ??= forgeVersion.group(2);
    }

    // Vanilla の起動行: `Loading Minecraft 1.21.1`(Loader の記載なし)
    final vanilla = _vanillaLoading.firstMatch(line);
    if (vanilla != null) minecraftVersion ??= vanilla.group(1);
  }

  return InstanceMetadata(
    minecraftVersion: minecraftVersion,
    modLoader: modLoader,
    modLoaderVersion: modLoaderVersion,
  );
}

final RegExp _fabricLoading = RegExp(
  r'Loading Minecraft (\d[\w.+-]*) with (Fabric|Quilt) Loader ([\w.+-]+)',
  caseSensitive: false,
);
final RegExp _vanillaLoading = RegExp(
  r'Loading Minecraft (\d[\w.+-]*)',
  caseSensitive: false,
);
final RegExp _fmlMcVersion = RegExp(
  r'--fml\.mcVersion[,\s]+\s*(\d[\w.+-]*)',
  caseSensitive: false,
);
final RegExp _fmlForgeVersion = RegExp(
  r'--fml\.(forge|neoForge)Version[,\s]+\s*([\w.+-]+)',
  caseSensitive: false,
);
