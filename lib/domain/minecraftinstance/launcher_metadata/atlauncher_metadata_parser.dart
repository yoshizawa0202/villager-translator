import 'dart:convert';

import '../mod_loader.dart';
import 'instance_metadata.dart';

/// `{instance}/instance.json` を解析する
/// (011-launcher-instance-discovery.md §8)。
///
/// 不正 JSON・必須キー欠落・型不一致では例外を投げず、読み取れた項目だけを返す。
/// インスタンス名を取得できない場合の「フォルダ名へのフォールバック」は
/// infrastructure 層の責務とする(ここはファイルシステムを知らない)。
InstanceMetadata parseAtLauncherInstance(String content) {
  final Object? decoded;
  try {
    decoded = jsonDecode(content);
  } catch (_) {
    return InstanceMetadata.empty;
  }
  if (decoded is! Map) return InstanceMetadata.empty;

  final id = decoded['id'];

  String? name;
  var modLoader = ModLoader.unknown;
  String? modLoaderVersion;
  DateTime? lastPlayed;

  final launcher = decoded['launcher'];
  if (launcher is Map) {
    final rawName = launcher['name'];
    if (rawName is String && rawName.trim().isNotEmpty) {
      name = rawName.trim();
    }

    final loaderVersion = launcher['loaderVersion'];
    if (loaderVersion is Map) {
      final type = loaderVersion['type'];
      if (type is String) modLoader = ModLoader.fromName(type);
      final version = loaderVersion['version'];
      if (version is String && version.trim().isNotEmpty) {
        modLoaderVersion = version.trim();
      }
    }

    final rawLastPlayed = launcher['lastPlayed'];
    if (rawLastPlayed is String) lastPlayed = DateTime.tryParse(rawLastPlayed);
  }

  return InstanceMetadata(
    name: name,
    minecraftVersion: id is String && id.trim().isNotEmpty ? id.trim() : null,
    modLoader: modLoader,
    modLoaderVersion: modLoaderVersion,
    lastPlayed: lastPlayed,
  );
}
