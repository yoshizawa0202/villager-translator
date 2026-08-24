import 'package:flutter_test/flutter_test.dart';
import 'package:villager_translator/domain/minecraftinstance/launcher_metadata/prism_metadata_parser.dart';
import 'package:villager_translator/domain/minecraftinstance/mod_loader.dart';

void main() {
  group('prismlauncher.cfg の InstanceDir(011 §6、AC-02)', () {
    test('未設定の場合は null を返す', () {
      expect(parsePrismInstanceDir('[General]\nLanguage=ja_JP\n'), isNull);
      expect(parsePrismInstanceDir('InstanceDir=\n'), isNull);
    });

    test('絶対パスをそのまま返す', () {
      expect(
        parsePrismInstanceDir('[General]\nInstanceDir=D:/Prism/instances\n'),
        'D:/Prism/instances',
      );
    });

    test('相対パスもそのまま返す(解決は infrastructure 層の責務)', () {
      expect(parsePrismInstanceDir('InstanceDir=./instances'), './instances');
    });

    test('コメント行・セクション見出し・壊れた行を読み飛ばす', () {
      final values = parseIniConfig(
        '# comment\n; comment\n[General]\n壊れた行\nname=Prominence II\n',
      );

      expect(values, {'name': 'Prominence II'});
    });
  });

  group('instance.cfg(011 §6)', () {
    test('名前と最終起動日時(ミリ秒エポック)を解析する', () {
      final metadata = parsePrismInstanceCfg(
        '[General]\nname=Prominence II\nlastLaunchTime=1700000000000\n',
      );

      expect(metadata.name, 'Prominence II');
      expect(
        metadata.lastPlayed,
        DateTime.fromMillisecondsSinceEpoch(1700000000000),
      );
    });

    test('値が無い・不正でも例外を投げず null になる', () {
      final metadata = parsePrismInstanceCfg(
        '[General]\nlastLaunchTime=だめな値\n',
      );

      expect(metadata.name, isNull);
      expect(metadata.lastPlayed, isNull);
    });
  });

  group('mmc-pack.json の components(011 §6)', () {
    test('net.minecraft から Minecraft バージョンを取得する', () {
      final metadata = parseMmcPack(
        '{"components": [{"uid": "net.minecraft", "version": "1.20.1"}]}',
      );

      expect(metadata.minecraftVersion, '1.20.1');
      // Loader コンポーネントが無い構成は Vanilla とみなす。
      expect(metadata.modLoader, ModLoader.vanilla);
    });

    test('uid ごとに Mod Loader を判定する', () {
      const cases = {
        'net.minecraftforge': ModLoader.forge,
        'net.neoforged': ModLoader.neoForge,
        'net.fabricmc.fabric-loader': ModLoader.fabric,
        'org.quiltmc.quilt-loader': ModLoader.quilt,
      };

      cases.forEach((uid, expected) {
        final metadata = parseMmcPack(
          '{"components": [{"uid": "net.minecraft", "version": "1.20.1"}, '
          '{"uid": "$uid", "version": "1.2.3"}]}',
        );

        expect(metadata.modLoader, expected, reason: 'uid: $uid');
        expect(metadata.modLoaderVersion, '1.2.3', reason: 'uid: $uid');
      });
    });

    test('不正 JSON・必須キー欠落・型不一致でも例外を投げない(011 AC-20)', () {
      for (final content in ['{壊れた', '[]', '{"components": 42}', '{}']) {
        final metadata = parseMmcPack(content);
        expect(metadata.minecraftVersion, isNull, reason: content);
        expect(metadata.modLoader, ModLoader.unknown, reason: content);
      }
    });
  });
}
