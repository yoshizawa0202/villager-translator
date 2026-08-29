import 'minecraft_launcher.dart';
import 'mod_loader.dart';

/// ランチャー固有の情報を翻訳処理へ持ち込まないための共通モデル
/// (011-launcher-instance-discovery.md §1)。
///
/// 既存の翻訳機能(MOD / クエスト / Patchouli / カスタムファイル)は
/// [rootPath] だけを受け取り、検出元ランチャーを一切知らない。
class MinecraftInstance {
  const MinecraftInstance({
    required this.id,
    required this.name,
    required this.launcher,
    required this.rootPath,
    this.minecraftVersion,
    this.modLoader = ModLoader.unknown,
    this.modLoaderVersion,
    this.iconPath,
    this.lastPlayed,
  });

  /// 検出元と正規化済み絶対パスから導出する安定 ID([buildInstanceId])。
  /// 再検出しても同じインスタンスには同じ値が付く。
  final String id;

  final String name;
  final MinecraftLauncher launcher;

  /// `mods/` `config/` `saves/` が直下にある Minecraft ルートの絶対パス。
  /// Prism のようにインスタンスフォルダ配下の `.minecraft/` が実体である場合、
  /// インスタンスフォルダではなく `.minecraft/` を格納する(§1)。
  final String rootPath;

  /// 取得できない場合は `null`(UI では `Unknown` と表示する)。
  final String? minecraftVersion;

  final ModLoader modLoader;

  /// 取得できない場合は `null`。
  final String? modLoaderVersion;

  /// ランチャーが提供するアイコンのパス。データ URI 形式は使用しない(§5)。
  final String? iconPath;

  /// 取得できない場合は `null`(一覧の並び順では末尾へ回す、§14)。
  final DateTime? lastPlayed;

  /// UI 表示用の Minecraft バージョン(未取得なら `Unknown`)。
  String get minecraftVersionLabel => minecraftVersion ?? 'Unknown';

  MinecraftInstance copyWith({
    String? id,
    String? name,
    MinecraftLauncher? launcher,
    String? rootPath,
    String? minecraftVersion,
    ModLoader? modLoader,
    String? modLoaderVersion,
    String? iconPath,
    DateTime? lastPlayed,
  }) {
    return MinecraftInstance(
      id: id ?? this.id,
      name: name ?? this.name,
      launcher: launcher ?? this.launcher,
      rootPath: rootPath ?? this.rootPath,
      minecraftVersion: minecraftVersion ?? this.minecraftVersion,
      modLoader: modLoader ?? this.modLoader,
      modLoaderVersion: modLoaderVersion ?? this.modLoaderVersion,
      iconPath: iconPath ?? this.iconPath,
      lastPlayed: lastPlayed ?? this.lastPlayed,
    );
  }
}

/// 検出元ランチャーと正規化済み絶対パスから安定 ID を導出する(§1)。
///
/// Windows のパスは大文字小文字を区別しないため、ID も小文字へ揃える
/// (同じ実体に対して常に同じ ID になるようにする)。
String buildInstanceId(MinecraftLauncher launcher, String normalizedRootPath) =>
    '${launcher.name}|${normalizedRootPath.toLowerCase()}';
