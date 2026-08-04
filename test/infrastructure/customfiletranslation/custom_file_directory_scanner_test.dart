import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:villager_translator/domain/customfiletranslation/custom_file_scan_entry.dart';
import 'package:villager_translator/infrastructure/customfiletranslation/custom_file_directory_scanner.dart';

Future<void> _writeFile(String path, String content) async {
  final file = File(path);
  await file.parent.create(recursive: true);
  await file.writeAsString(content);
}

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp(
      'custom_file_scanner_test_',
    );
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('サブディレクトリを含め .json .snbt が再帰的に検出される(受け入れ条件1)', () async {
    await _writeFile(p.join(tempDir.path, 'a.json'), '{"title": "Hello"}');
    await _writeFile(
      p.join(tempDir.path, 'nested', 'deep', 'b.snbt'),
      'raw snbt content',
    );
    await _writeFile(p.join(tempDir.path, 'ignored.txt'), 'not a target');

    final entries = await scanCustomFilesDirectory(rootDirectory: tempDir);

    expect(entries, hasLength(2));
    expect(entries.map((e) => e.relativePath).toSet(), {
      'a.json',
      'nested/deep/b.snbt',
    });
  });

  test('translated/ 配下は前回出力の再検出を避けるためスキャン対象から除外される', () async {
    await _writeFile(p.join(tempDir.path, 'a.json'), '{"title": "Hello"}');
    await _writeFile(
      p.join(tempDir.path, 'translated', 'ja_jp_a.json'),
      '{"title": "こんにちは"}',
    );

    final entries = await scanCustomFilesDirectory(rootDirectory: tempDir);

    expect(entries, hasLength(1));
    expect(entries.single.relativePath, 'a.json');
  });

  test('対象言語ファイルが translated/ 配下に既にあっても常に全件が翻訳対象として選択可能(受け入れ条件2)', () async {
    await _writeFile(p.join(tempDir.path, 'a.json'), '{"title": "Hello"}');
    await _writeFile(
      p.join(tempDir.path, 'translated', 'ja_jp_a.json'),
      '{"title": "既存訳"}',
    );

    final entries = await scanCustomFilesDirectory(rootDirectory: tempDir);

    expect(entries, hasLength(1));
    expect(entries.single.sourceEntries, {'title': 'Hello'});
  });

  test('ネストした JSON がドット/ブラケット記法にフラット化されて検出される(受け入れ条件3、4)', () async {
    await _writeFile(
      p.join(tempDir.path, 'nested.json'),
      '{"a": {"b": ["x", "y"]}, "count": 5}',
    );

    final entries = await scanCustomFilesDirectory(rootDirectory: tempDir);

    expect(entries.single.sourceEntries, {'a.b[0]': 'x', 'a.b[1]': 'y'});
    expect(entries.single.jsonRoot, isNotNull);
  });

  test('SNBT はファイル全文が単一の翻訳単位として保持される(受け入れ条件6)', () async {
    await _writeFile(p.join(tempDir.path, 'a.snbt'), 'title: "Chapter"');

    final entries = await scanCustomFilesDirectory(rootDirectory: tempDir);

    expect(entries.single.format, CustomFileFormat.snbt);
    expect(entries.single.sourceEntries, {
      kCustomSnbtContentKey: 'title: "Chapter"',
    });
  });

  test('壊れた JSON ファイルが1件あっても、他のファイルのスキャンは継続される', () async {
    await _writeFile(p.join(tempDir.path, 'broken.json'), '{not valid json');
    await _writeFile(p.join(tempDir.path, 'ok.json'), '{"a": "b"}');

    final entries = await scanCustomFilesDirectory(rootDirectory: tempDir);

    expect(entries, hasLength(1));
    expect(entries.single.relativePath, 'ok.json');
  });

  test('文字列の葉ノードが1件もない JSON はスキャン結果に含まれない', () async {
    await _writeFile(
      p.join(tempDir.path, 'numbers.json'),
      '{"a": 1, "b": true}',
    );

    final entries = await scanCustomFilesDirectory(rootDirectory: tempDir);

    expect(entries, isEmpty);
  });

  test('何も存在しない場合は空リストを返す', () async {
    final entries = await scanCustomFilesDirectory(rootDirectory: tempDir);
    expect(entries, isEmpty);
  });
}
