import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:villager_translator/domain/customfiletranslation/custom_file_output_builder.dart';
import 'package:villager_translator/domain/customfiletranslation/custom_file_scan_entry.dart';
import 'package:villager_translator/domain/customfiletranslation/custom_file_translation_service.dart';

CustomFileTranslationOutput _jsonOutput(
  String relativePath,
  dynamic jsonRoot,
  Map<String, String> translated,
) {
  return CustomFileTranslationOutput(
    entry: CustomFileScanEntry(
      format: CustomFileFormat.json,
      absolutePath: '/root/$relativePath',
      relativePath: relativePath,
      sourceEntries: translated,
      jsonRoot: jsonRoot,
    ),
    entries: translated,
  );
}

CustomFileTranslationOutput _snbtOutput(
  String relativePath,
  String translatedContent,
) {
  return CustomFileTranslationOutput(
    entry: CustomFileScanEntry(
      format: CustomFileFormat.snbt,
      absolutePath: '/root/$relativePath',
      relativePath: relativePath,
      sourceEntries: {kCustomSnbtContentKey: 'original'},
    ),
    entries: {kCustomSnbtContentKey: translatedContent},
  );
}

void main() {
  group('buildCustomFileOutputFiles', () {
    test('出力ファイル名は {targetLanguage}_{ファイル名} になる(受け入れ条件7)', () {
      final output = _jsonOutput(
        'sub/dir/a.json',
        jsonDecode('{"title": "x"}'),
        {'title': '訳x'},
      );

      final files = buildCustomFileOutputFiles([output], 'ja_jp');

      expect(files.single.fileName, 'ja_jp_a.json');
      expect(files.single.content, contains('訳x'));
    });

    test('JSON は構造・非翻訳キーを保った完全な JSON として再構成される', () {
      final root = jsonDecode('{"title": "x", "count": 3}');
      final output = _jsonOutput('a.json', root, {'title': '訳x'});

      final files = buildCustomFileOutputFiles([output], 'ja_jp');
      final decoded = jsonDecode(files.single.content);

      expect(decoded, {'title': '訳x', 'count': 3});
    });

    test('SNBT は翻訳結果の全文がそのまま出力される', () {
      final output = _snbtOutput('a.snbt', 'translated content');

      final files = buildCustomFileOutputFiles([output], 'ja_jp');

      expect(files.single.fileName, 'ja_jp_a.snbt');
      expect(files.single.content, 'translated content');
    });

    test('異なるサブディレクトリの同名ファイルが選択された場合、2件目以降のファイル名に連番が付与される(受け入れ条件8)', () {
      final outputs = [
        _jsonOutput('dirA/common.json', jsonDecode('{"k": "a"}'), {'k': '訳a'}),
        _jsonOutput('dirB/common.json', jsonDecode('{"k": "b"}'), {'k': '訳b'}),
      ];

      final files = buildCustomFileOutputFiles(outputs, 'ja_jp');
      final names = files.map((f) => f.fileName).toList();

      // 相対パス昇順(dirA → dirB)で処理され、名前の一意性が保たれる。
      expect(names, ['ja_jp_common.json', 'ja_jp_common_2.json']);
      expect(names.toSet().length, 2);
    });
  });
}
