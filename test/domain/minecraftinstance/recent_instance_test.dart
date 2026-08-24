import 'package:flutter_test/flutter_test.dart';
import 'package:villager_translator/domain/minecraftinstance/minecraft_launcher.dart';
import 'package:villager_translator/domain/minecraftinstance/recent_instance.dart';

RecentInstance _recent(String id, [DateTime? usedAt]) => RecentInstance(
  id: id,
  name: id,
  launcher: MinecraftLauncher.prism,
  rootPath: 'D:/mc/$id',
  usedAt: usedAt ?? DateTime(2026, 8, 24),
);

void main() {
  test('最近使用は最大 5 件で古いものから破棄される(011 §15.4、AC-19)', () {
    var list = <RecentInstance>[];
    for (var i = 1; i <= 7; i++) {
      list = pushRecentInstance(list, _recent('i$i'));
    }

    expect(list, hasLength(kMaxRecentInstances));
    expect(list.map((e) => e.id).toList(), ['i7', 'i6', 'i5', 'i4', 'i3']);
  });

  test('同じインスタンスは重複させず先頭へ移動する', () {
    final list = pushRecentInstance([_recent('a'), _recent('b')], _recent('b'));

    expect(list.map((e) => e.id).toList(), ['b', 'a']);
  });

  test('壊れた JSON の 1 件は読み飛ばせるよう null を返す(011 §15.5)', () {
    expect(RecentInstance.tryFromJson(null), isNull);
    expect(RecentInstance.tryFromJson('文字列'), isNull);
    expect(RecentInstance.tryFromJson({'id': 'a'}), isNull);
    expect(RecentInstance.tryFromJson({'rootPath': 'D:/mc'}), isNull);
  });

  test('復元できる JSON からは値を復元する', () {
    final restored = RecentInstance.tryFromJson(_recent('a').toJson());

    expect(restored, isNotNull);
    expect(restored!.id, 'a');
    expect(restored.launcher, MinecraftLauncher.prism);
    expect(restored.rootPath, 'D:/mc/a');
  });
}
