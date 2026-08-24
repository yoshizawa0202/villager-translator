import 'minecraft_instance.dart';
import 'minecraft_launcher.dart';

/// 最近使用したインスタンスの保存件数の上限
/// (011-launcher-instance-discovery.md §15.4)。
const int kMaxRecentInstances = 5;

/// 最近使用した Minecraft インスタンス 1 件分の記録(§15.4)。
///
/// 一覧上部から素早く再開するための最小限の情報だけを保持する。表示に必要な
/// メタデータ(Minecraft バージョン等)は再検出時に取得し直す。
class RecentInstance {
  const RecentInstance({
    required this.id,
    required this.name,
    required this.launcher,
    required this.rootPath,
    required this.usedAt,
  });

  final String id;
  final String name;
  final MinecraftLauncher launcher;
  final String rootPath;
  final DateTime usedAt;

  factory RecentInstance.fromInstance(
    MinecraftInstance instance,
    DateTime usedAt,
  ) => RecentInstance(
    id: instance.id,
    name: instance.name,
    launcher: instance.launcher,
    rootPath: instance.rootPath,
    usedAt: usedAt,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'launcher': launcher.name,
    'rootPath': rootPath,
    'usedAt': usedAt.toIso8601String(),
  };

  /// JSON から復元する。値が欠損・不正な場合は `null` を返し、呼び出し側が
  /// その 1 件だけを読み飛ばせるようにする(ファイル全体を捨てない)。
  static RecentInstance? tryFromJson(Object? json) {
    if (json is! Map) return null;

    final id = json['id'];
    final rootPath = json['rootPath'];
    if (id is! String || id.isEmpty) return null;
    if (rootPath is! String || rootPath.isEmpty) return null;

    final name = json['name'];
    final launcherName = json['launcher'];
    final usedAt = json['usedAt'];

    return RecentInstance(
      id: id,
      name: name is String && name.isNotEmpty ? name : rootPath,
      launcher: _launcherFromName(launcherName),
      rootPath: rootPath,
      usedAt: usedAt is String
          ? (DateTime.tryParse(usedAt) ??
                DateTime.fromMillisecondsSinceEpoch(0))
          : DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}

MinecraftLauncher _launcherFromName(Object? name) {
  for (final launcher in MinecraftLauncher.values) {
    if (launcher.name == name) return launcher;
  }
  return MinecraftLauncher.manual;
}

/// [recent] を先頭へ追加した最近使用一覧を返す(§15.4)。
///
/// 同じインスタンス([RecentInstance.id])が既にあれば重複させず先頭へ移動し、
/// [kMaxRecentInstances] を超えた分は古いものから破棄する。
List<RecentInstance> pushRecentInstance(
  List<RecentInstance> existing,
  RecentInstance recent,
) {
  final result = [recent, ...existing.where((e) => e.id != recent.id)];
  if (result.length <= kMaxRecentInstances) return result;
  return result.sublist(0, kMaxRecentInstances);
}
