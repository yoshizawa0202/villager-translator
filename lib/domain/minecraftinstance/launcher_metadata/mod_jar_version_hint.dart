import 'dart:convert';

import '../mod_loader.dart';
import 'instance_metadata.dart';

/// `mods/` 内の JAR から Minecraft バージョン範囲を推定する
/// (011-launcher-instance-discovery.md §12 の第3段)。
///
/// `fabric.mod.json` の `depends.minecraft`、または `META-INF/mods.toml` の
/// `[[dependencies]]` 宣言(`modId = "minecraft"` の `versionRange`)から、
/// 「その MOD が対象としている Minecraft バージョン」を1つ選ぶ。
///
/// バージョン範囲は `>=1.20.1 <1.21` や `[1.20.1,1.21)` のような表記を取り得る
/// ため、範囲に現れる最初の具体的なバージョンを採用する。推定値であり、確定値
/// ではない(ランチャーメタデータが読めた場合はそちらを優先する)。
InstanceMetadata hintFromFabricModJson(String content) {
  final Object? decoded;
  try {
    decoded = jsonDecode(_stripBom(content));
  } catch (_) {
    return InstanceMetadata.empty;
  }
  if (decoded is! Map) return InstanceMetadata.empty;

  final depends = decoded['depends'];
  if (depends is! Map) {
    return const InstanceMetadata(modLoader: ModLoader.fabric);
  }

  return InstanceMetadata(
    minecraftVersion: _firstConcreteVersion(depends['minecraft']),
    modLoader: ModLoader.fabric,
  );
}

/// `META-INF/mods.toml` の `[[dependencies.*]]` から `minecraft` の
/// `versionRange` を読み取る。Loader 種別は `neoforge` 依存の有無で判定する。
InstanceMetadata hintFromModsToml(String content) {
  final lines = const LineSplitter().convert(_stripBom(content));

  String? currentModId;
  String? minecraftRange;
  var modLoader = ModLoader.forge;

  for (final rawLine in lines) {
    final line = rawLine.trim();
    if (line.startsWith('[[dependencies')) {
      currentModId = null;
      continue;
    }

    final modId = _tomlStringValue(line, 'modId');
    if (modId != null) {
      currentModId = modId.toLowerCase();
      if (currentModId == 'neoforge') modLoader = ModLoader.neoForge;
      continue;
    }

    final range = _tomlStringValue(line, 'versionRange');
    if (range != null && currentModId == 'minecraft') {
      minecraftRange ??= range;
    }
  }

  return InstanceMetadata(
    minecraftVersion: _firstConcreteVersion(minecraftRange),
    modLoader: modLoader,
  );
}

final RegExp _versionPattern = RegExp(r'\d+(?:\.\d+)+');

/// バージョン範囲表記から最初の具体的なバージョン(`1.20.1` など)を取り出す。
String? _firstConcreteVersion(Object? range) {
  if (range is! String) return null;
  return _versionPattern.firstMatch(range)?.group(0);
}

String? _tomlStringValue(String line, String key) {
  final pattern = RegExp(
    '^${RegExp.escape(key)}'
    r'\s*=\s*"([^"]*)"',
  );
  return pattern.firstMatch(line)?.group(1);
}

const _bom = '\uFEFF';

String _stripBom(String text) =>
    text.startsWith(_bom) ? text.substring(1) : text;
