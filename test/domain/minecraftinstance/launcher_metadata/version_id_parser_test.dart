import 'package:flutter_test/flutter_test.dart';
import 'package:villager_translator/domain/minecraftinstance/launcher_metadata/version_id_parser.dart';
import 'package:villager_translator/domain/minecraftinstance/mod_loader.dart';

void main() {
  test('バニラのバージョン ID をそのまま Minecraft バージョンとして解析する(011 §5)', () {
    final parsed = parseLastVersionId('1.21.1');

    expect(parsed.minecraftVersion, '1.21.1');
    expect(parsed.modLoader, ModLoader.vanilla);
    expect(parsed.modLoaderVersion, isNull);
  });

  test('NeoForge の ID は Minecraft バージョンを含まないため null になる(011 §5)', () {
    final parsed = parseLastVersionId('neoforge-21.1.72');

    expect(parsed.minecraftVersion, isNull);
    expect(parsed.modLoader, ModLoader.neoForge);
    expect(parsed.modLoaderVersion, '21.1.72');
  });

  test('Forge の ID から Minecraft バージョンと Loader バージョンを解析する(011 §5)', () {
    final parsed = parseLastVersionId('1.20.1-forge-47.2.20');

    expect(parsed.minecraftVersion, '1.20.1');
    expect(parsed.modLoader, ModLoader.forge);
    expect(parsed.modLoaderVersion, '47.2.20');
  });

  test('Fabric の ID から Loader バージョンと Minecraft バージョンを解析する(011 §5)', () {
    final parsed = parseLastVersionId('fabric-loader-0.16.9-1.21.1');

    expect(parsed.minecraftVersion, '1.21.1');
    expect(parsed.modLoader, ModLoader.fabric);
    expect(parsed.modLoaderVersion, '0.16.9');
  });

  test('Quilt の ID から Loader バージョンと Minecraft バージョンを解析する(011 §5)', () {
    final parsed = parseLastVersionId('quilt-loader-0.26.4-1.21.1');

    expect(parsed.minecraftVersion, '1.21.1');
    expect(parsed.modLoader, ModLoader.quilt);
    expect(parsed.modLoaderVersion, '0.26.4');
  });

  test('照合は大文字小文字を無視する(011 §5)', () {
    final parsed = parseLastVersionId('1.20.1-FORGE-47.2.20');

    expect(parsed.minecraftVersion, '1.20.1');
    expect(parsed.modLoader, ModLoader.forge);
  });

  test('解析できない値でも例外を投げず Unknown を返す(011 AC-11、AC-12)', () {
    for (final raw in [null, '', '   ', 'まったく別の文字列']) {
      final parsed = parseLastVersionId(raw);
      expect(parsed.minecraftVersion, isNull, reason: 'input: $raw');
      expect(parsed.modLoader, ModLoader.unknown, reason: 'input: $raw');
    }
  });
}
