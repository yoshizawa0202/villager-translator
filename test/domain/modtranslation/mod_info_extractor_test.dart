import 'package:flutter_test/flutter_test.dart';
import 'package:villager_translator/domain/modtranslation/mod_info.dart';
import 'package:villager_translator/domain/modtranslation/mod_info_extractor.dart';

void main() {
  group('extractModInfoFromFabricJson', () {
    test('id/name/version を取得できる', () {
      final info = extractModInfoFromFabricJson(
        '{"id": "examplemod", "name": "Example Mod", "version": "1.2.3"}',
      );

      expect(info, isNotNull);
      expect(info!.id, 'examplemod');
      expect(info.name, 'Example Mod');
      expect(info.version, '1.2.3');
      expect(info.source, ModInfoSource.fabricModJson);
    });

    test('id が欠損している場合は null を返す', () {
      final info = extractModInfoFromFabricJson('{"name": "Example Mod"}');
      expect(info, isNull);
    });

    test('壊れた JSON では null を返す', () {
      final info = extractModInfoFromFabricJson('{not valid json');
      expect(info, isNull);
    });
  });

  group('extractModInfoFromModsToml', () {
    test('modId/displayName/version を取得できる', () {
      const toml = '''
modLoader="javafml"
loaderVersion="[40,)"

[[mods]]
modId="examplemod"
version="2.0.0"
displayName="Example Forge Mod"
''';
      final info = extractModInfoFromModsToml(toml);

      expect(info, isNotNull);
      expect(info!.id, 'examplemod');
      expect(info.name, 'Example Forge Mod');
      expect(info.version, '2.0.0');
      expect(info.source, ModInfoSource.forgeModsToml);
    });

    test('displayName/version が省略されている場合はフォールバックする', () {
      const toml = '''
[[mods]]
modId="minimalmod"
''';
      final info = extractModInfoFromModsToml(toml);

      expect(info, isNotNull);
      expect(info!.id, 'minimalmod');
      expect(info.name, 'minimalmod');
      expect(info.version, 'unknown');
    });

    test('[[mods]] セクションが存在しない場合は null を返す', () {
      final info = extractModInfoFromModsToml('modLoader="javafml"');
      expect(info, isNull);
    });
  });

  group('extractModInfoFromManifest', () {
    test('常に unknown な ModInfo を返す', () {
      final info = extractModInfoFromManifest('Manifest-Version: 1.0');
      expect(info.id, 'unknown');
      expect(info.source, ModInfoSource.manifest);
    });
  });

  group('resolveModInfo', () {
    test('fabric.mod.json が優先される', () {
      final info = resolveModInfo(
        fabricModJson: '{"id": "fabricmod", "name": "F", "version": "1.0"}',
        modsToml: '[[mods]]\nmodId="forgemod"',
        manifestMf: 'Manifest-Version: 1.0',
      );

      expect(info!.id, 'fabricmod');
      expect(info.source, ModInfoSource.fabricModJson);
    });

    test('fabric.mod.json が解決できない場合は mods.toml にフォールバックする', () {
      final info = resolveModInfo(
        fabricModJson: '{not valid json',
        modsToml: '[[mods]]\nmodId="forgemod"',
        manifestMf: 'Manifest-Version: 1.0',
      );

      expect(info!.id, 'forgemod');
      expect(info.source, ModInfoSource.forgeModsToml);
    });

    test('fabric/mods.toml いずれも解決できない場合は MANIFEST.MF にフォールバックする', () {
      final info = resolveModInfo(
        fabricModJson: null,
        modsToml: null,
        manifestMf: 'Manifest-Version: 1.0',
      );

      expect(info!.id, 'unknown');
      expect(info.source, ModInfoSource.manifest);
    });

    test('いずれの情報源も存在しない場合は null を返す(スキップ対象)', () {
      final info = resolveModInfo(
        fabricModJson: null,
        modsToml: null,
        manifestMf: null,
      );

      expect(info, isNull);
    });
  });
}
