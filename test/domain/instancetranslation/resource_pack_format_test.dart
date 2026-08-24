import 'package:flutter_test/flutter_test.dart';
import 'package:villager_translator/domain/instancetranslation/resource_pack_format.dart';
import 'package:villager_translator/domain/modtranslation/mod_translation_service.dart';
import 'package:villager_translator/domain/modtranslation/resource_pack_builder.dart';
import 'package:villager_translator/domain/translation/lang_codec.dart';

void main() {
  group('Minecraft バージョン → pack_format(012 §11、AC-14)', () {
    test('対応表の各境界値で正しい値を返す', () {
      const cases = {
        '1.6.1': 1,
        '1.8.9': 1,
        '1.9': 2,
        '1.10.2': 2,
        '1.11': 3,
        '1.12.2': 3,
        '1.13': 4,
        '1.14.4': 4,
        '1.15': 5,
        '1.16.1': 5,
        '1.16.2': 6,
        '1.16.5': 6,
        '1.17': 7,
        '1.17.1': 7,
        '1.18': 8,
        '1.18.2': 8,
        '1.19': 9,
        '1.19.2': 9,
        '1.19.3': 12,
        '1.19.4': 13,
        '1.20': 15,
        '1.20.1': 15,
        '1.20.2': 18,
        '1.20.3': 22,
        '1.20.4': 22,
        '1.20.5': 32,
        '1.20.6': 32,
        '1.21': 34,
        '1.21.1': 34,
      };

      cases.forEach((version, expected) {
        final resolution = resolveResourcePackFormat(version);
        expect(resolution.packFormat, expected, reason: version);
        expect(resolution.isEstimated, isFalse, reason: version);
        expect(resolution.isFallback, isFalse, reason: version);
      });
    });

    test('バージョン不明・対応表より古い場合は既定値 9 へフォールバックする', () {
      for (final version in [null, '', '   ', 'Unknown', '1.5.2', '1.2.5']) {
        final resolution = resolveResourcePackFormat(version);
        expect(resolution.packFormat, kResourcePackFormat, reason: '$version');
        expect(resolution.isFallback, isTrue, reason: '$version');
      }
    });

    test('対応表より新しい場合は最大エントリの値を推定値として使う', () {
      final resolution = resolveResourcePackFormat('1.99.0');

      expect(resolution.packFormat, kResourcePackFormatTable.last.packFormat);
      expect(resolution.isEstimated, isTrue);
      expect(resolution.isFallback, isFalse);
    });

    test('不正なバージョン文字列でも例外を投げない', () {
      for (final version in ['1.x', '24w14a', 'forge-47.2.20', '...']) {
        expect(
          () => resolveResourcePackFormat(version),
          returnsNormally,
          reason: version,
        );
      }
    });

    test('接尾辞つきのバージョンでも数値部分から判定する', () {
      expect(resolveResourcePackFormat('1.20.1-forge').packFormat, 15);
    });
  });

  group('pack_format の任意引数(012 AC-15)', () {
    test('渡した pack_format が pack.mcmeta へ出力される', () {
      expect(buildPackMcmeta(packFormat: 34), contains('"pack_format": 34'));

      final files = buildResourcePackFiles(
        outputs: const <ModTranslationOutput>[],
        targetLanguageId: 'ja_jp',
        packFormat: 15,
      );
      expect(files['pack.mcmeta'], contains('"pack_format": 15'));
    });

    test('省略した場合は従来どおり 9 が出力される(既存経路の非破壊)', () {
      expect(buildPackMcmeta(), contains('"pack_format": 9'));

      final files = buildResourcePackFiles(
        outputs: const [
          ModTranslationOutput(
            modId: 'moda',
            format: LangFormat.json,
            entries: {'a': 'A'},
          ),
        ],
        targetLanguageId: 'ja_jp',
      );
      expect(files['pack.mcmeta'], contains('"pack_format": 9'));
    });
  });
}
