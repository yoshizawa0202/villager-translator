import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:villager_translator/domain/settings/app_settings.dart';
import 'package:villager_translator/infrastructure/settings/settings_repository.dart';

void main() {
  late Directory tempDir;
  late SettingsRepository repository;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync(
      'villager_translator_settings_test',
    );
    repository = SettingsRepository.forApplicationSupportDirectory(tempDir);
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('SettingsRepository', () {
    test('ファイルが存在しない場合は既定値を返す', () async {
      final loaded = await repository.load();
      expect(loaded.llm.provider, AppSettings.defaults().llm.provider);
    });

    test('save したファイルの内容が load で復元できる', () async {
      final settings = AppSettings.defaults().copyWith(
        translation: AppSettings.defaults().translation.copyWith(
          resourcePackName: 'MyPack',
        ),
      );

      await repository.save(settings);
      final loaded = await repository.load();

      expect(loaded.translation.resourcePackName, 'MyPack');
    });

    test('破損した JSON ファイルからは例外を投げずに既定値を返す', () async {
      await repository.settingsFile.parent.create(recursive: true);
      await repository.settingsFile.writeAsString('{ this is not valid json');

      final loaded = await repository.load();
      expect(loaded.llm.provider, AppSettings.defaults().llm.provider);
    });

    test('保存された生ファイルに API キー文字列が出現しない', () async {
      const fakeApiKey = 'sk-super-secret-fake-key-should-not-leak';
      await repository.save(AppSettings.defaults());

      final rawText = await repository.settingsFile.readAsString();
      expect(rawText.contains(fakeApiKey), isFalse);
      expect(rawText.contains('apiKey'), isFalse);
    });
  });
}
