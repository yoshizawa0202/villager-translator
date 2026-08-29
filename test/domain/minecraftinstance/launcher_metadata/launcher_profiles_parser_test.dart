import 'package:flutter_test/flutter_test.dart';
import 'package:villager_translator/domain/minecraftinstance/launcher_metadata/launcher_profiles_parser.dart';
import 'package:villager_translator/domain/minecraftinstance/mod_loader.dart';

void main() {
  test('Installation ごとに名前・gameDir・バージョン・最終起動日時を解析する(011 §5)', () {
    final entries = parseLauncherProfiles('''
{
  "profiles": {
    "latest": {
      "name": "Latest Release",
      "lastVersionId": "1.21.1",
      "lastUsed": "2026-08-01T10:00:00.000Z"
    },
    "neoforge": {
      "name": "NeoForge 1.21.1",
      "lastVersionId": "neoforge-21.1.72",
      "gameDir": "D:/Minecraft/NeoForge1211"
    }
  }
}
''');

    expect(entries, hasLength(2));
    final byKey = {for (final e in entries) e.key: e.metadata};

    expect(byKey['latest']!.name, 'Latest Release');
    expect(byKey['latest']!.minecraftVersion, '1.21.1');
    expect(byKey['latest']!.gameDirectory, isNull);
    expect(byKey['latest']!.lastPlayed, isNotNull);

    expect(byKey['neoforge']!.modLoader, ModLoader.neoForge);
    expect(byKey['neoforge']!.gameDirectory, isNotNull);
  });

  test('name が空の場合は lastVersionId を名前に使う(011 §5)', () {
    final entries = parseLauncherProfiles(
      '{"profiles": {"a": {"name": "", "lastVersionId": "1.20.1"}}}',
    );

    expect(entries.single.metadata.name, '1.20.1');
  });

  test('データ URI 形式のアイコンは使用しない(011 §5)', () {
    final entries = parseLauncherProfiles(
      '{"profiles": {"a": {"lastVersionId": "1.20.1", '
      '"icon": "data:image/png;base64,AAAA"}}}',
    );

    expect(entries.single.metadata.iconPath, isNull);
  });

  test('不正 JSON・必須キー欠落でも例外を投げず空を返す(011 AC-20)', () {
    expect(parseLauncherProfiles('{壊れた'), isEmpty);
    expect(parseLauncherProfiles('[]'), isEmpty);
    expect(parseLauncherProfiles('{"profiles": 42}'), isEmpty);
    expect(parseLauncherProfiles('{}'), isEmpty);
  });
}
