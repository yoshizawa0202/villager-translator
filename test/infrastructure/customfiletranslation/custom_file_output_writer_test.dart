import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:villager_translator/domain/customfiletranslation/custom_file_output_builder.dart';
import 'package:villager_translator/infrastructure/customfiletranslation/custom_file_output_writer.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('custom_file_writer_test_');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('出力先ディレクトリが存在しない場合は作成したうえでファイルを書き出す', () async {
    final outputDirectory = Directory(p.join(tempDir.path, 'translated'));

    final written = await writeCustomFileOutputFiles(
      outputDirectory: outputDirectory,
      files: const [
        CustomFileOutputFile(fileName: 'ja_jp_a.json', content: '{"a":"訳"}'),
      ],
    );

    expect(written, hasLength(1));
    expect(
      await File(p.join(outputDirectory.path, 'ja_jp_a.json')).readAsString(),
      '{"a":"訳"}',
    );
  });
}
