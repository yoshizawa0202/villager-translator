import 'package:flutter_test/flutter_test.dart';
import 'package:villager_translator/domain/minecraftinstance/launcher_metadata/curseforge_metadata_parser.dart';
import 'package:villager_translator/domain/minecraftinstance/launcher_metadata/curseforge_settings_parser.dart';
import 'package:villager_translator/domain/minecraftinstance/mod_loader.dart';

void main() {
  group('minecraftinstance.json(011 §7、AC-03)', () {
    test('名前・gameVersion・baseModLoader.name を解析する', () {
      final metadata = parseCurseForgeInstance('''
{
  "name": "Better MC",
  "gameVersion": "1.20.1",
  "lastPlayed": "2026-07-20T09:30:00.000Z",
  "baseModLoader": {"name": "forge-47.2.20"}
}
''');

      expect(metadata.name, 'Better MC');
      expect(metadata.minecraftVersion, '1.20.1');
      expect(metadata.modLoader, ModLoader.forge);
      expect(metadata.modLoaderVersion, '47.2.20');
      expect(metadata.lastPlayed, isNotNull);
    });

    test('baseModLoader.forgeVersion からも Loader バージョンを取得する', () {
      final metadata = parseCurseForgeInstance(
        '{"name": "A", "baseModLoader": '
        '{"name": "forge", "forgeVersion": "47.2.20"}}',
      );

      expect(metadata.modLoader, ModLoader.forge);
      expect(metadata.modLoaderVersion, '47.2.20');
    });

    test('不正 JSON・必須キー欠落でも例外を投げない(011 AC-20)', () {
      for (final content in ['{壊れた', '[]', '{}', '{"baseModLoader": 42}']) {
        final metadata = parseCurseForgeInstance(content);
        expect(metadata.name, isNull, reason: content);
        expect(metadata.modLoader, ModLoader.unknown, reason: content);
      }
    });
  });

  group('CurseForge 設定の Modding Folder(011 §7)', () {
    test('入れ子になっていても候補キーから取得できる', () {
      expect(
        parseCurseForgeModdingFolder(
          '{"minecraft": {"gameInstancePath": "D:/curseforge/minecraft"}}',
        ),
        'D:/curseforge/minecraft',
      );
    });

    test('該当キーが無い・不正 JSON では null を返す(標準パスへフォールバック)', () {
      expect(parseCurseForgeModdingFolder('{"other": 1}'), isNull);
      expect(parseCurseForgeModdingFolder('{壊れた'), isNull);
    });
  });
}
