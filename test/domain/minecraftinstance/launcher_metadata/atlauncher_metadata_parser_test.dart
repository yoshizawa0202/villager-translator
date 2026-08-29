import 'package:flutter_test/flutter_test.dart';
import 'package:villager_translator/domain/minecraftinstance/launcher_metadata/atlauncher_metadata_parser.dart';
import 'package:villager_translator/domain/minecraftinstance/mod_loader.dart';

void main() {
  test('launcher.name・id・loaderVersion を解析する(011 §8、AC-04)', () {
    final metadata = parseAtLauncherInstance('''
{
  "id": "1.20.1",
  "launcher": {
    "name": "All the Mods 9",
    "loaderVersion": {"type": "neoforge", "version": "21.1.72"}
  }
}
''');

    expect(metadata.name, 'All the Mods 9');
    expect(metadata.minecraftVersion, '1.20.1');
    expect(metadata.modLoader, ModLoader.neoForge);
    expect(metadata.modLoaderVersion, '21.1.72');
  });

  test(
    'launcher.name を取得できない場合は name が null になる(フォルダ名は infrastructure 層で補う)',
    () {
      final metadata = parseAtLauncherInstance('{"id": "1.20.1"}');

      expect(metadata.name, isNull);
      expect(metadata.minecraftVersion, '1.20.1');
    },
  );

  test('不正 JSON・型不一致でも例外を投げない(011 AC-20)', () {
    for (final content in ['{壊れた', '[]', '{}', '{"launcher": "文字列"}']) {
      final metadata = parseAtLauncherInstance(content);
      expect(metadata.name, isNull, reason: content);
      expect(metadata.modLoader, ModLoader.unknown, reason: content);
    }
  });
}
