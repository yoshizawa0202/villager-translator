import 'dart:convert';

import 'instance_metadata.dart';
import 'version_id_parser.dart';

/// 公式 Minecraft Launcher の `launcher_profiles.json` から読み取った
/// Installation 1 件分(011-launcher-instance-discovery.md §5)。
class LauncherProfileEntry {
  const LauncherProfileEntry({required this.key, required this.metadata});

  /// `profiles` オブジェクトのキー(表示名が空のときの識別子)。
  final String key;

  final InstanceMetadata metadata;
}

/// `launcher_profiles.json` の `profiles` を解析する(§5)。
///
/// 不正 JSON・必須キー欠落・型不一致では例外を投げず、解析できたものだけを返す
/// (AC-20: ランチャー設定の破損でアプリ全体を止めない)。
List<LauncherProfileEntry> parseLauncherProfiles(String content) {
  final Object? decoded;
  try {
    decoded = jsonDecode(content);
  } catch (_) {
    return const [];
  }
  if (decoded is! Map) return const [];

  final profiles = decoded['profiles'];
  if (profiles is! Map) return const [];

  final entries = <LauncherProfileEntry>[];
  for (final entry in profiles.entries) {
    final key = entry.key;
    final value = entry.value;
    if (key is! String || value is! Map) continue;

    final lastVersionId = value['lastVersionId'];
    final parsed = parseLastVersionId(
      lastVersionId is String ? lastVersionId : null,
    );

    final rawName = value['name'];
    final name = rawName is String && rawName.trim().isNotEmpty
        ? rawName.trim()
        : (lastVersionId is String && lastVersionId.trim().isNotEmpty
              ? lastVersionId.trim()
              : key);

    final gameDir = value['gameDir'];
    final lastUsed = value['lastUsed'];

    entries.add(
      LauncherProfileEntry(
        key: key,
        metadata: InstanceMetadata(
          name: name,
          minecraftVersion: parsed.minecraftVersion,
          modLoader: parsed.modLoader,
          modLoaderVersion: parsed.modLoaderVersion,
          lastPlayed: lastUsed is String ? DateTime.tryParse(lastUsed) : null,
          gameDirectory: gameDir is String && gameDir.trim().isNotEmpty
              ? gameDir.trim()
              : null,
          iconPath: _iconPathOrNull(value['icon']),
        ),
      ),
    );
  }
  return entries;
}

/// `icon` はデータ URI 形式(`data:image/png;base64,...`)と組み込みアイコン名の
/// 両方を取り得る。データ URI 形式は使用しない(§5)。
String? _iconPathOrNull(Object? icon) {
  if (icon is! String) return null;
  final trimmed = icon.trim();
  if (trimmed.isEmpty) return null;
  if (trimmed.toLowerCase().startsWith('data:')) return null;
  return trimmed;
}
