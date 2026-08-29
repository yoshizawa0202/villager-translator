import 'minecraft_instance.dart';
import 'mod_loader.dart';

/// 複数の Detector が同じ Minecraft ルートを返した場合に、一覧へ重複表示しない
/// ようにまとめる(011-launcher-instance-discovery.md §11)。
///
/// 重複判定キーは正規化済み絶対パス([MinecraftInstance.rootPath] は
/// infrastructure 層で正規化済みとして渡される)。名前は実体を特定しないため
/// 判定に使わない。同名・別パスは両方保持する(AC-10)。
///
/// [instances] は「メタデータ確定判定を行った Detector が先」の順で渡す。
/// 先に現れた要素のランチャー種別を採用し、後続からは欠けているメタデータのみを
/// 補完する。
List<MinecraftInstance> deduplicateInstances(
  List<MinecraftInstance> instances,
) {
  final merged = <String, MinecraftInstance>{};
  final order = <String>[];

  for (final instance in instances) {
    final key = instance.rootPath.toLowerCase();
    final existing = merged[key];
    if (existing == null) {
      merged[key] = instance;
      order.add(key);
      continue;
    }
    merged[key] = _mergeInstances(existing, instance);
  }

  return [for (final key in order) merged[key]!];
}

/// [base] を優先しつつ、[other] が持つより充実したメタデータで補完する(§11)。
///
/// ランチャー種別・名前・ID は [base](先に検出された側)のものを維持する。
MinecraftInstance _mergeInstances(
  MinecraftInstance base,
  MinecraftInstance other,
) {
  return MinecraftInstance(
    id: base.id,
    name: base.name,
    launcher: base.launcher,
    rootPath: base.rootPath,
    minecraftVersion: base.minecraftVersion ?? other.minecraftVersion,
    modLoader: base.modLoader == ModLoader.unknown
        ? other.modLoader
        : base.modLoader,
    modLoaderVersion: base.modLoaderVersion ?? other.modLoaderVersion,
    iconPath: base.iconPath ?? other.iconPath,
    lastPlayed: _laterOf(base.lastPlayed, other.lastPlayed),
  );
}

DateTime? _laterOf(DateTime? a, DateTime? b) {
  if (a == null) return b;
  if (b == null) return a;
  return a.isAfter(b) ? a : b;
}

/// 一覧の並び順(§14)。
///
/// 「最終起動日時の降順 → インスタンス名の昇順」とし、[MinecraftInstance.lastPlayed]
/// が取得できないインスタンスは名前順で末尾に並べる。
List<MinecraftInstance> sortInstancesForDisplay(
  List<MinecraftInstance> instances,
) {
  final sorted = instances.toList();
  sorted.sort((a, b) {
    final aPlayed = a.lastPlayed;
    final bPlayed = b.lastPlayed;
    if (aPlayed != null && bPlayed != null) {
      final byDate = bPlayed.compareTo(aPlayed);
      if (byDate != 0) return byDate;
    } else if (aPlayed != null) {
      return -1;
    } else if (bPlayed != null) {
      return 1;
    }
    return a.name.toLowerCase().compareTo(b.name.toLowerCase());
  });
  return sorted;
}
