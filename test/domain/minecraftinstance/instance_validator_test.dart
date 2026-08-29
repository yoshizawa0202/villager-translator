import 'package:flutter_test/flutter_test.dart';
import 'package:villager_translator/domain/minecraftinstance/instance_validator.dart';

void main() {
  test('マーカー 2 つ以上でインスタンスと判定する(011 §10、AC-08)', () {
    expect(looksLikeMinecraftInstance(['mods', 'config']), isTrue);
    expect(
      looksLikeMinecraftInstance(['saves', 'options.txt', 'logs']),
      isTrue,
    );
  });

  test('マーカー 1 つ以下では判定しない(011 AC-08)', () {
    expect(looksLikeMinecraftInstance(['mods']), isFalse);
    expect(looksLikeMinecraftInstance(['readme.txt', 'backup']), isFalse);
    expect(looksLikeMinecraftInstance(const []), isFalse);
  });

  test('比較は大文字小文字を区別しない(Windows)', () {
    expect(looksLikeMinecraftInstance(['Mods', 'CONFIG']), isTrue);
    expect(countInstanceMarkers(['Mods', 'Saves', 'other']), 2);
  });

  test(
    'ランチャールートは instances / profiles / prismlauncher.cfg で判定する(011 §15.1)',
    () {
      expect(looksLikeLauncherRoot(['instances']), isTrue);
      expect(looksLikeLauncherRoot(['profiles']), isTrue);
      expect(looksLikeLauncherRoot(['prismlauncher.cfg']), isTrue);
      expect(looksLikeLauncherRoot(['mods', 'config']), isFalse);
    },
  );
}
