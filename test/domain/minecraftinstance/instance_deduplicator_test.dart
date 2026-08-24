import 'package:flutter_test/flutter_test.dart';
import 'package:villager_translator/domain/minecraftinstance/instance_deduplicator.dart';
import 'package:villager_translator/domain/minecraftinstance/minecraft_instance.dart';
import 'package:villager_translator/domain/minecraftinstance/minecraft_launcher.dart';
import 'package:villager_translator/domain/minecraftinstance/mod_loader.dart';

MinecraftInstance _instance({
  required String name,
  required String rootPath,
  MinecraftLauncher launcher = MinecraftLauncher.prism,
  String? minecraftVersion,
  ModLoader modLoader = ModLoader.unknown,
  String? modLoaderVersion,
  DateTime? lastPlayed,
}) => MinecraftInstance(
  id: buildInstanceId(launcher, rootPath),
  name: name,
  launcher: launcher,
  rootPath: rootPath,
  minecraftVersion: minecraftVersion,
  modLoader: modLoader,
  modLoaderVersion: modLoaderVersion,
  lastPlayed: lastPlayed,
);

void main() {
  test('同一の正規化済み絶対パスは 1 件へまとめられる(011 AC-09)', () {
    final result = deduplicateInstances([
      _instance(name: 'A', rootPath: 'D:/mc/inst'),
      _instance(
        name: 'A(別 Detector)',
        rootPath: 'D:/mc/inst',
        launcher: MinecraftLauncher.manual,
      ),
    ]);

    expect(result, hasLength(1));
    // 先に検出した側(メタデータ確定判定を行った Detector)を採用する。
    expect(result.single.launcher, MinecraftLauncher.prism);
  });

  test('大文字小文字だけが異なるパスは同一と判定する(011 §11)', () {
    final result = deduplicateInstances([
      _instance(name: 'A', rootPath: 'D:/MC/Inst'),
      _instance(name: 'A', rootPath: 'd:/mc/inst'),
    ]);

    expect(result, hasLength(1));
  });

  test('名前が同一でもパスが異なれば両方保持する(011 AC-10)', () {
    final result = deduplicateInstances([
      _instance(name: 'Prominence II', rootPath: 'D:/prism/PromII/.minecraft'),
      _instance(
        name: 'Prominence II',
        rootPath: 'C:/curseforge/Instances/Prominence II',
        launcher: MinecraftLauncher.curseForge,
      ),
    ]);

    expect(result, hasLength(2));
  });

  test('マージ時にメタデータが充実している側の値を採用する(011 AC-09)', () {
    final result = deduplicateInstances([
      _instance(name: 'A', rootPath: 'D:/mc/inst'),
      _instance(
        name: 'A',
        rootPath: 'D:/mc/inst',
        minecraftVersion: '1.20.1',
        modLoader: ModLoader.fabric,
        modLoaderVersion: '0.16.9',
        lastPlayed: DateTime(2026, 8, 1),
      ),
    ]);

    expect(result.single.minecraftVersion, '1.20.1');
    expect(result.single.modLoader, ModLoader.fabric);
    expect(result.single.modLoaderVersion, '0.16.9');
    expect(result.single.lastPlayed, DateTime(2026, 8, 1));
  });

  test('並び順は最終起動日時の降順 → 名前の昇順、日時なしは末尾(011 §14)', () {
    final result = sortInstancesForDisplay([
      _instance(name: 'Zzz', rootPath: 'D:/1'),
      _instance(name: 'Aaa', rootPath: 'D:/2'),
      _instance(
        name: 'Old',
        rootPath: 'D:/3',
        lastPlayed: DateTime(2026, 1, 1),
      ),
      _instance(
        name: 'New',
        rootPath: 'D:/4',
        lastPlayed: DateTime(2026, 8, 1),
      ),
    ]);

    expect(result.map((e) => e.name).toList(), ['New', 'Old', 'Aaa', 'Zzz']);
  });
}
