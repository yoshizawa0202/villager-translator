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

  test('save を同時に複数回呼び出しても例外にならず最終値が復元できる(011 AC-16)', () async {
    final store = InstanceStore.forApplicationSupportDirectory(tempDir);

    await Future.wait([
      for (var i = 0; i < 10; i++)
        store.save(InstanceStoreData(manualPaths: ['D:/path$i'])),
    ]);

    final loaded = await store.load();
    expect(loaded.manualPaths.single, 'D:/path9');
  });

  test('保存後に一時ファイル・バックアップファイルが残らない(011 §15.5 原子的書き込み)', () async {
    final store = InstanceStore.forApplicationSupportDirectory(tempDir);

    await store.save(const InstanceStoreData(manualPaths: ['D:/a']));
    await store.save(const InstanceStoreData(manualPaths: ['D:/b']));

    final remaining =
        tempDir
            .listSync()
            .map((e) => p.basename(e.path))
            .where((name) => name.startsWith('instances.json'))
            .toList()
          ..sort();
    expect(remaining, ['instances.json']);
    expect((await store.load()).manualPaths.single, 'D:/b');
  });

  test('既存ファイルがある状態で保存しても内容が置き換わる(011 §15.5)', () async {
    final file = File(p.join(tempDir.path, 'instances.json'));
    await file.writeAsString('{"manualPaths":["D:/old"]}');

    await InstanceStore(
      file,
    ).save(const InstanceStoreData(manualPaths: ['D:/new']));

    expect((await InstanceStore(file).load()).manualPaths.single, 'D:/new');
  });
}
