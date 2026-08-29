import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:villager_translator/domain/common/cancellation_token.dart';
import 'package:villager_translator/infrastructure/minecraftinstance/deep_instance_search.dart';

import '../../test_support/fake_instance_tree.dart';
import '../../test_support/fake_windows_environment.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('deep_search_test_');
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  String at(List<String> segments) => p.joinAll([tempDir.path, ...segments]);

  test('固定ドライブのルートから再帰探索してインスタンスを見つける(011 AC-18)', () async {
    await createInstanceMarkers(at(['Games', 'MyPack']));

    final found = await searchInstancesDeeply(
      environment: FakeWindowsEnvironment(driveRoots: [tempDir.path]),
    );

    expect(found.map((e) => e.name).toList(), ['MyPack']);
  });

  test('深さ上限より深いディレクトリへは降りない(011 §15.3)', () async {
    await createInstanceMarkers(at(['a', 'b', 'c', 'Deep']));

    final shallow = await searchInstancesDeeply(
      environment: FakeWindowsEnvironment(driveRoots: [tempDir.path]),
      maxDepth: 2,
    );
    final deep = await searchInstancesDeeply(
      environment: FakeWindowsEnvironment(driveRoots: [tempDir.path]),
      maxDepth: 6,
    );

    expect(shallow, isEmpty);
    expect(deep.map((e) => e.name).toList(), ['Deep']);
  });

  test('除外ディレクトリ配下へは降りない(011 §15.3)', () async {
    await createInstanceMarkers(at(['Windows', 'Hidden']));
    await createInstanceMarkers(at(['node_modules', 'Hidden2']));

    final found = await searchInstancesDeeply(
      environment: FakeWindowsEnvironment(driveRoots: [tempDir.path]),
    );

    expect(found, isEmpty);
  });

  test('インスタンスと判定したディレクトリ配下へはそれ以上降りない(011 §15.3)', () async {
    await createInstanceMarkers(at(['Pack']));
    await createInstanceMarkers(at(['Pack', 'mods', 'Nested']));

    final found = await searchInstancesDeeply(
      environment: FakeWindowsEnvironment(driveRoots: [tempDir.path]),
    );

    expect(found.map((e) => e.name).toList(), ['Pack']);
  });

  test('キャンセルすると探索を打ち切る(011 AC-18)', () async {
    await createInstanceMarkers(at(['Games', 'MyPack']));
    final token = CancellationToken()..cancel();

    final found = await searchInstancesDeeply(
      environment: FakeWindowsEnvironment(driveRoots: [tempDir.path]),
      cancellationToken: token,
    );

    expect(found, isEmpty);
  });

  test('存在しないドライブルートでも中断しない(アクセス権限エラーと同じ扱い)', () async {
    await createInstanceMarkers(at(['Games', 'MyPack']));

    final found = await searchInstancesDeeply(
      environment: FakeWindowsEnvironment(
        driveRoots: [
          at(['missing-drive']),
          tempDir.path,
        ],
      ),
    );

    expect(found.map((e) => e.name).toList(), ['MyPack']);
  });

  test('探索中のパスを進捗として通知する(011 §15.3)', () async {
    await createInstanceMarkers(at(['Games', 'MyPack']));
    final visited = <String>[];

    await searchInstancesDeeply(
      environment: FakeWindowsEnvironment(driveRoots: [tempDir.path]),
      onDirectoryVisited: visited.add,
    );

    expect(visited, isNotEmpty);
    expect(visited.first, tempDir.path);
  });
}
