import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:villager_translator/domain/minecraftinstance/minecraft_launcher.dart';
import 'package:villager_translator/domain/minecraftinstance/mod_loader.dart';
import 'package:villager_translator/infrastructure/minecraftinstance/atlauncher_detector.dart';
import 'package:villager_translator/infrastructure/minecraftinstance/curseforge_launcher_detector.dart';
import 'package:villager_translator/infrastructure/minecraftinstance/manual_instance_detector.dart';
import 'package:villager_translator/infrastructure/minecraftinstance/modrinth_launcher_detector.dart';
import 'package:villager_translator/infrastructure/minecraftinstance/official_launcher_detector.dart';
import 'package:villager_translator/infrastructure/minecraftinstance/prism_launcher_detector.dart';

import '../../test_support/fake_instance_tree.dart';
import '../../test_support/fake_windows_environment.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('launcher_detector_test_');
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  String at(List<String> segments) => p.joinAll([tempDir.path, ...segments]);

  group('公式 Minecraft Launcher(011 AC-01)', () {
    test('Installation ごとに検出し、gameDir は独立したインスタンスになる', () async {
      await createInstanceMarkers(at(['appdata', '.minecraft']));
      await createInstanceMarkers(at(['D', 'NeoForge1211']));
      await writeTextFile(
        at(['appdata', '.minecraft', 'launcher_profiles.json']),
        '{"profiles": {'
        '"latest": {"name": "Latest Release", "lastVersionId": "1.21.1"}, '
        '"neo": {"name": "NeoForge 1.21.1", '
        '"lastVersionId": "neoforge-21.1.72", '
        '"gameDir": "${at(['D', 'NeoForge1211']).replaceAll(r'\', '/')}"}}}',
      );

      final instances = await OfficialLauncherDetector(
        environment: FakeWindowsEnvironment(appData: at(['appdata'])),
      ).discoverInstances();

      final byName = {for (final i in instances) i.name: i};
      expect(byName['Latest Release']!.minecraftVersion, '1.21.1');
      expect(byName['NeoForge 1.21.1']!.modLoader, ModLoader.neoForge);
      expect(
        byName['NeoForge 1.21.1']!.rootPath.toLowerCase(),
        contains('neoforge1211'),
      );
    });

    test('標準パスが存在しない場合は空リストを返す', () async {
      final instances = await OfficialLauncherDetector(
        environment: FakeWindowsEnvironment(appData: at(['missing'])),
      ).discoverInstances();

      expect(instances, isEmpty);
    });

    test('設定が壊れていても例外を投げない(011 AC-20)', () async {
      await createInstanceMarkers(at(['appdata', '.minecraft']));
      await writeTextFile(
        at(['appdata', '.minecraft', 'launcher_profiles.json']),
        '{壊れた',
      );

      final instances = await OfficialLauncherDetector(
        environment: FakeWindowsEnvironment(appData: at(['appdata'])),
      ).discoverInstances();

      // 設定は読めなくても `.minecraft` 自体はマーカー判定で検出できる。
      expect(instances, hasLength(1));
      expect(instances.single.launcher, MinecraftLauncher.official);
    });
  });

  group('Prism Launcher(011 AC-02)', () {
    Future<void> createPrismInstance(
      String instancesDir,
      String name, {
      String minecraftFolder = '.minecraft',
    }) async {
      final instanceDir = p.join(instancesDir, name);
      await writeTextFile(
        p.join(instanceDir, 'instance.cfg'),
        '[General]\nname=$name\nlastLaunchTime=1700000000000\n',
      );
      await writeTextFile(
        p.join(instanceDir, 'mmc-pack.json'),
        '{"components": ['
        '{"uid": "net.minecraft", "version": "1.20.1"}, '
        '{"uid": "net.fabricmc.fabric-loader", "version": "0.16.9"}]}',
      );
      if (minecraftFolder.isNotEmpty) {
        await createInstanceMarkers(p.join(instanceDir, minecraftFolder));
      }
    }

    test('標準パス配下のインスタンスを検出し、rootPath が .minecraft を指す', () async {
      await createPrismInstance(
        at(['appdata', 'PrismLauncher', 'instances']),
        'Prominence II',
      );

      final instances = await PrismLauncherDetector(
        environment: FakeWindowsEnvironment(appData: at(['appdata'])),
      ).discoverInstances();

      expect(instances, hasLength(1));
      expect(instances.single.name, 'Prominence II');
      expect(instances.single.minecraftVersion, '1.20.1');
      expect(instances.single.modLoader, ModLoader.fabric);
      expect(instances.single.rootPath, endsWith('.minecraft'));
      expect(instances.single.lastPlayed, isNotNull);
    });

    test('旧構成の minecraft フォルダも rootPath として解決する', () async {
      await createPrismInstance(
        at(['appdata', 'PrismLauncher', 'instances']),
        'Old',
        minecraftFolder: 'minecraft',
      );

      final instances = await PrismLauncherDetector(
        environment: FakeWindowsEnvironment(appData: at(['appdata'])),
      ).discoverInstances();

      expect(instances.single.rootPath, endsWith('minecraft'));
    });

    test('.minecraft も minecraft も無い場合はマーカー判定にかける', () async {
      await createPrismInstance(
        at(['appdata', 'PrismLauncher', 'instances']),
        'NoRoot',
        minecraftFolder: '',
      );

      final instances = await PrismLauncherDetector(
        environment: FakeWindowsEnvironment(appData: at(['appdata'])),
      ).discoverInstances();

      // 設定ファイルしか無いフォルダはマーカーを満たさないため検出しない。
      expect(instances, isEmpty);
    });

    test('prismlauncher.cfg の InstanceDir が検索対象になる', () async {
      await writeTextFile(
        at(['appdata', 'PrismLauncher', 'prismlauncher.cfg']),
        '[General]\nInstanceDir=${at(['custom-instances']).replaceAll(r'\', '/')}\n',
      );
      await createPrismInstance(at(['custom-instances']), 'Custom');

      final instances = await PrismLauncherDetector(
        environment: FakeWindowsEnvironment(appData: at(['appdata'])),
      ).discoverInstances();

      expect(instances.map((e) => e.name).toList(), ['Custom']);
    });

    test('追加パスを Portable 版のランチャールートとして扱う(011 AC-06)', () async {
      await writeTextFile(at(['portable', 'prismlauncher.cfg']), '[General]\n');
      await createPrismInstance(at(['portable', 'instances']), 'Portable');

      final instances = await PrismLauncherDetector(
        environment: FakeWindowsEnvironment(appData: at(['missing'])),
        additionalRootPaths: [
          at(['portable']),
        ],
      ).discoverInstances();

      expect(instances.map((e) => e.name).toList(), ['Portable']);
    });
  });

  group('CurseForge(011 AC-03)', () {
    Future<void> createCurseForgeInstance(
      String instancesDir,
      String name,
    ) async {
      await createInstanceMarkers(p.join(instancesDir, name));
      await writeTextFile(
        p.join(instancesDir, name, 'minecraftinstance.json'),
        '{"name": "$name", "gameVersion": "1.20.1", '
        '"baseModLoader": {"name": "forge-47.2.20"}}',
      );
    }

    test('標準の Modding Folder 配下を検出し、rootPath がインスタンスフォルダ自体になる', () async {
      await createCurseForgeInstance(
        at(['user', 'curseforge', 'minecraft', 'Instances']),
        'Better MC',
      );

      final instances = await CurseForgeLauncherDetector(
        environment: FakeWindowsEnvironment(userProfile: at(['user'])),
      ).discoverInstances();

      expect(instances, hasLength(1));
      expect(instances.single.name, 'Better MC');
      expect(instances.single.minecraftVersion, '1.20.1');
      expect(instances.single.modLoader, ModLoader.forge);
      expect(instances.single.rootPath, endsWith('Better MC'));
    });

    test('設定から取得した Modding Folder を標準パスより優先する', () async {
      await createCurseForgeInstance(
        at(['user', 'curseforge', 'minecraft', 'Instances']),
        'Standard',
      );
      await createCurseForgeInstance(at(['custom', 'Instances']), 'Configured');
      await writeTextFile(
        at(['appdata', 'CurseForge', 'Settings', 'settings.json']),
        '{"minecraft": {"gameInstancePath": '
        '"${at(['custom']).replaceAll(r'\', '/')}"}}',
      );

      final instances = await CurseForgeLauncherDetector(
        environment: FakeWindowsEnvironment(
          appData: at(['appdata']),
          userProfile: at(['user']),
        ),
      ).discoverInstances();

      // 設定由来のフォルダが先に来る(標準パスへもフォールバックする)。
      expect(instances.first.name, 'Configured');
      expect(instances.map((e) => e.name), contains('Standard'));
    });

    test('標準パスが存在しない場合は空リストを返す', () async {
      final instances = await CurseForgeLauncherDetector(
        environment: FakeWindowsEnvironment(userProfile: at(['missing'])),
      ).discoverInstances();

      expect(instances, isEmpty);
    });
  });

  group('ATLauncher(011 AC-04)', () {
    test('instances 配下を instance.json とともに検出する', () async {
      await createInstanceMarkers(
        at(['appdata', 'ATLauncher', 'instances', 'ATM9']),
      );
      await writeTextFile(
        at(['appdata', 'ATLauncher', 'instances', 'ATM9', 'instance.json']),
        '{"id": "1.20.1", "launcher": {"name": "All the Mods 9", '
        '"loaderVersion": {"type": "neoforge", "version": "21.1.72"}}}',
      );

      final instances = await ATLauncherDetector(
        environment: FakeWindowsEnvironment(appData: at(['appdata'])),
      ).discoverInstances();

      expect(instances, hasLength(1));
      expect(instances.single.name, 'All the Mods 9');
      expect(instances.single.minecraftVersion, '1.20.1');
      expect(instances.single.modLoader, ModLoader.neoForge);
      expect(instances.single.rootPath, endsWith('ATM9'));
    });

    test('追加パスを Portable 版のランチャールートとして扱う(011 AC-06)', () async {
      await createInstanceMarkers(at(['portable-at', 'instances', 'X']));
      await writeTextFile(
        at(['portable-at', 'instances', 'X', 'instance.json']),
        '{"id": "1.20.1"}',
      );

      final instances = await ATLauncherDetector(
        environment: FakeWindowsEnvironment(appData: at(['missing'])),
        additionalRootPaths: [
          at(['portable-at']),
        ],
      ).discoverInstances();

      // launcher.name が無いためフォルダ名へフォールバックする。
      expect(instances.map((e) => e.name).toList(), ['X']);
    });
  });

  group('Modrinth App(011 AC-05)', () {
    test('profiles 配下をマーカー判定で検出する(SQLite を読まない)', () async {
      await createInstanceMarkers(
        at(['appdata', 'ModrinthApp', 'profiles', 'Fabulously Optimized']),
      );

      final instances = await ModrinthLauncherDetector(
        environment: FakeWindowsEnvironment(appData: at(['appdata'])),
      ).discoverInstances();

      expect(instances, hasLength(1));
      expect(instances.single.name, 'Fabulously Optimized');
      // メタデータが無いため Unknown のまま検出が成立する(011 AC-11、AC-12)。
      expect(instances.single.minecraftVersion, isNull);
      expect(instances.single.modLoader, ModLoader.unknown);
      expect(instances.single.rootPath, endsWith('Fabulously Optimized'));
    });

    test('旧ディレクトリ com.modrinth.theseus も確認する', () async {
      await createInstanceMarkers(
        at(['appdata', 'com.modrinth.theseus', 'profiles', 'Old Profile']),
      );

      final instances = await ModrinthLauncherDetector(
        environment: FakeWindowsEnvironment(appData: at(['appdata'])),
      ).discoverInstances();

      expect(instances.map((e) => e.name).toList(), ['Old Profile']);
    });

    test('マーカーを 1 つしか持たないフォルダは除外する(011 AC-08)', () async {
      await Directory(
        at(['appdata', 'ModrinthApp', 'profiles', 'NotAnInstance', 'mods']),
      ).create(recursive: true);

      final instances = await ModrinthLauncherDetector(
        environment: FakeWindowsEnvironment(appData: at(['appdata'])),
      ).discoverInstances();

      expect(instances, isEmpty);
    });
  });

  group('手動追加(011 §15.1、AC-06)', () {
    test('追加パス自体がインスタンス検証を満たせば manual として登録する', () async {
      await createInstanceMarkers(at(['custom', 'MyServerPack']));

      final instances = await ManualInstanceDetector(
        paths: [
          at(['custom', 'MyServerPack']),
        ],
      ).discoverInstances();

      expect(instances, hasLength(1));
      expect(instances.single.launcher, MinecraftLauncher.manual);
      expect(instances.single.name, 'MyServerPack');
    });

    test('インスタンス検証を満たさないパスは登録しない', () async {
      await Directory(at(['custom', 'Empty'])).create(recursive: true);

      final instances = await ManualInstanceDetector(
        paths: [
          at(['custom', 'Empty']),
          at(['missing']),
        ],
      ).discoverInstances();

      expect(instances, isEmpty);
    });
  });
}
