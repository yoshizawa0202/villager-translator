import '../mod_loader.dart';

/// 公式ランチャーの `lastVersionId` を解析した結果
/// (011-launcher-instance-discovery.md §5)。
class ParsedVersionId {
  const ParsedVersionId({
    this.minecraftVersion,
    this.modLoader = ModLoader.unknown,
    this.modLoaderVersion,
  });

  final String? minecraftVersion;
  final ModLoader modLoader;
  final String? modLoaderVersion;
}

final RegExp _fabricLike = RegExp(
  r'^(fabric|quilt)-loader-([\w.+]+?)-(\d[\w.+-]*)$',
  caseSensitive: false,
);
final RegExp _mcPrefixedLoader = RegExp(
  r'^(\d[\w.+]*)-(forge|neoforge|fabric|quilt)-([\w.+-]+)$',
  caseSensitive: false,
);
final RegExp _loaderOnly = RegExp(
  r'^(forge|neoforge|fabric|quilt)-([\w.+-]+)$',
  caseSensitive: false,
);
final RegExp _plainVersion = RegExp(r'^\d[\w.+-]*$');

/// `lastVersionId` から Minecraft バージョン・Mod Loader・Loader バージョンを
/// 解析する(§5 の対応表)。照合は大文字小文字を無視する。
///
/// 解析できない場合は例外を投げず、`minecraftVersion` を `null`、
/// `modLoader` を [ModLoader.unknown] とした結果を返す(AC-11、AC-12)。
/// NeoForge の ID は Minecraft バージョンを含まないため、そこは呼び出し側の
/// 多段フォールバック(§12)で補う。
ParsedVersionId parseLastVersionId(String? raw) {
  final value = raw?.trim() ?? '';
  if (value.isEmpty) return const ParsedVersionId();

  final fabricLike = _fabricLike.firstMatch(value);
  if (fabricLike != null) {
    return ParsedVersionId(
      minecraftVersion: fabricLike.group(3),
      modLoader: ModLoader.fromName(fabricLike.group(1)),
      modLoaderVersion: fabricLike.group(2),
    );
  }

  final mcPrefixed = _mcPrefixedLoader.firstMatch(value);
  if (mcPrefixed != null) {
    return ParsedVersionId(
      minecraftVersion: mcPrefixed.group(1),
      modLoader: ModLoader.fromName(mcPrefixed.group(2)),
      modLoaderVersion: mcPrefixed.group(3),
    );
  }

  final loaderOnly = _loaderOnly.firstMatch(value);
  if (loaderOnly != null) {
    return ParsedVersionId(
      modLoader: ModLoader.fromName(loaderOnly.group(1)),
      modLoaderVersion: loaderOnly.group(2),
    );
  }

  if (_plainVersion.hasMatch(value)) {
    return ParsedVersionId(
      minecraftVersion: value,
      modLoader: ModLoader.vanilla,
    );
  }

  return const ParsedVersionId();
}
