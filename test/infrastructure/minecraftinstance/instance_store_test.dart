import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:villager_translator/domain/minecraftinstance/minecraft_launcher.dart';
import 'package:villager_translator/domain/minecraftinstance/recent_instance.dart';
import 'package:villager_translator/infrastructure/minecraftinstance/instance_store.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('instance_store_test_');
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  test('手動追加パスと最近使用を保存し読み込める(011 AC-16、AC-19)', () async {
    final store = InstanceStore.forApplicationSupportDirectory(tempDir);

    await store.save(
      InstanceStoreData(
        manualPaths: ['D:/custom/instance'],
        recentInstances: [
          RecentInstance(
            id: 'x',
            name: 'Prominence II',
            launcher: MinecraftLauncher.prism,
            rootPath: 'D:/prism/PromII/.minecraft',
            usedAt: DateTime(2026, 8, 24),
          ),
        ],
      ),
    );

    final loaded = await store.load();

    expect(loaded.manualPaths, ['D:/custom/instance']);
    expect(loaded.recentInstances.single.name, 'Prominence II');
    expect(loaded.recentInstances.single.launcher, MinecraftLauncher.prism);
  });

  test('ファイルが存在しない場合は空状態を返す(011 §15.5)', () async {
    final store = InstanceStore.forApplicationSupportDirectory(tempDir);

    final loaded = await store.load();

    expect(loaded.manualPaths, isEmpty);
    expect(loaded.recentInstances, isEmpty);
  });

  test('ファイルが壊れている場合も例外を投げず空状態へフォールバックする(011 §15.5)', () async {
    final file = File(p.join(tempDir.path, 'instances.json'));
    await file.writeAsString('{壊れた');

    final loaded = await InstanceStore(file).load();

    expect(loaded.manualPaths, isEmpty);
    expect(loaded.recentInstances, isEmpty);
  });

  test('settings.json とは別ファイルへ保存する(設計判断: 永続化先を分ける)', () async {
    final store = InstanceStore.forApplicationSupportDirectory(tempDir);
    await store.save(const InstanceStoreData(manualPaths: ['D:/a']));

    expect(await File(p.join(tempDir.path, 'instances.json')).exists(), isTrue);
    expect(await File(p.join(tempDir.path, 'settings.json')).exists(), isFalse);
  });
}
