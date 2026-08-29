import '../mod_loader.dart';

/// ランチャー設定ファイルから読み取った 1 インスタンス分のメタデータ
/// (011-launcher-instance-discovery.md §5〜§9)。
///
/// 「文字列 → モデル」の純粋な変換結果であり、実ファイルシステムへのアクセスは
/// 伴わない。infrastructure 層の Detector がこれを [MinecraftInstance] へ
/// 組み立てる。
class InstanceMetadata {
  const InstanceMetadata({
    this.name,
    this.minecraftVersion,
    this.modLoader = ModLoader.unknown,
    this.modLoaderVersion,
    this.lastPlayed,
    this.gameDirectory,
    this.iconPath,
  });

  /// 何も読み取れなかったことを表す空のメタデータ。
  static const InstanceMetadata empty = InstanceMetadata();

  final String? name;
  final String? minecraftVersion;
  final ModLoader modLoader;
  final String? modLoaderVersion;
  final DateTime? lastPlayed;

  /// 公式ランチャーの `gameDir` のように、Minecraft ルートが明示されている場合の値。
  final String? gameDirectory;

  final String? iconPath;

  /// 1 件でも意味のある値を読み取れたかどうか。
  bool get isEmpty =>
      name == null &&
      minecraftVersion == null &&
      modLoader == ModLoader.unknown &&
      modLoaderVersion == null &&
      lastPlayed == null &&
      gameDirectory == null;

  InstanceMetadata copyWith({
    String? name,
    String? minecraftVersion,
    ModLoader? modLoader,
    String? modLoaderVersion,
    DateTime? lastPlayed,
    String? gameDirectory,
    String? iconPath,
  }) {
    return InstanceMetadata(
      name: name ?? this.name,
      minecraftVersion: minecraftVersion ?? this.minecraftVersion,
      modLoader: modLoader ?? this.modLoader,
      modLoaderVersion: modLoaderVersion ?? this.modLoaderVersion,
      lastPlayed: lastPlayed ?? this.lastPlayed,
      gameDirectory: gameDirectory ?? this.gameDirectory,
      iconPath: iconPath ?? this.iconPath,
    );
  }
}
