import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:villager_translator/domain/minecraftinstance/minecraft_instance.dart';
import 'package:villager_translator/domain/minecraftinstance/minecraft_launcher.dart';
import 'package:villager_translator/features/instance_detail/instance_analysis_controller.dart';
import 'package:villager_translator/features/instance_detail/instance_detail_page.dart';
import 'package:villager_translator/features/settings/settings_controller.dart';
import 'package:villager_translator/features/shell/main_shell_page.dart';

import '../../test_support/fake_jar_builder.dart';
import '../../test_support/in_memory_api_key_store.dart';
import '../../test_support/in_memory_settings_repository.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('instance_detail_test_');
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  MinecraftInstance buildInstance() => MinecraftInstance(
    id: 'test-instance',
    name: 'Prominence II',
    launcher: MinecraftLauncher.prism,
    rootPath: tempDir.path,
    minecraftVersion: '1.20.1',
  );

  Future<InstanceAnalysisController> pumpPage(WidgetTester tester) async {
    // 解析結果は縦に長いため、ListView の遅延生成で画面外の項目が
    // 未構築にならないよう、十分な高さのテスト画面を用意する。
    tester.view.physicalSize = const Size(1200, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final settingsController = SettingsController(
      repository: InMemorySettingsRepository(),
      apiKeyStore: InMemoryApiKeyStore(),
    );
    await settingsController.load();

    final analysisController = InstanceAnalysisController(
      instance: buildInstance(),
    );
    await tester.runAsync(analysisController.analyze);

    await tester.pumpWidget(
      ChangeNotifierProvider<SettingsController>.value(
        value: settingsController,
        child: MaterialApp(
          home: InstanceDetailPage(
            instance: buildInstance(),
            controller: analysisController,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return analysisController;
  }

  testWidgets('解析結果に件数・内訳・クエスト形式・ガイドブックが表示される(011 AC-15)', (tester) async {
    await tester.runAsync(() async {
      await writeFakeJar(File(p.join(tempDir.path, 'mods', 'moda.jar')), {
        'fabric.mod.json': '{"id": "moda", "name": "Mod A", "version": "1.0"}',
        'assets/moda/lang/en_us.json': '{"item.a": "Item A"}',
      });
      await writeFakeJar(File(p.join(tempDir.path, 'mods', 'modb.jar')), {
        'fabric.mod.json': '{"id": "modb", "name": "Mod B", "version": "1.0"}',
        'assets/modb/lang/en_us.json': '{"item.b": "Item B"}',
        'assets/modb/lang/ja_jp.json': '{"item.b": "アイテムB"}',
      });
    });

    await pumpPage(tester);

    expect(find.byKey(const Key('instanceAnalysisResult')), findsOneWidget);
    expect(find.byKey(const Key('analysisModJarCount')), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(const Key('analysisModJarCount'))).data,
      '2 個',
    );
    expect(
      tester
          .widget<Text>(find.byKey(const Key('analysisTranslatableModCount')))
          .data,
      '2 個',
    );
    expect(
      tester
          .widget<Text>(find.byKey(const Key('analysisTranslatedModCount')))
          .data,
      '1 個',
    );
    expect(
      tester
          .widget<Text>(find.byKey(const Key('analysisUntranslatedModCount')))
          .data,
      '1 個',
    );
    expect(
      find.byKey(const Key('analysisQuestFamily_ftbQuests')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('analysisQuestFamily_betterQuesting')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('analysisNoGuidebooks')), findsOneWidget);
  });

  testWidgets(
    '4 タブ画面へ遷移すると rootPath が ProfileDirectoryController へ渡る(011 §13)',
    (tester) async {
      await tester.runAsync(() async {
        await Directory(p.join(tempDir.path, 'config')).create(recursive: true);
      });

      await pumpPage(tester);

      await tester.tap(find.byKey(const Key('openTabbedShellButton')));
      await tester.pumpAndSettle();

      final shell = tester.widget<MainShellPage>(find.byType(MainShellPage));
      expect(
        shell.profileDirectoryController!.profileDirectory!.path,
        tempDir.path,
      );
      // AppBar にインスタンス名・バージョン・Loader を表示する。
      expect(shell.instance!.name, 'Prominence II');
      expect(
        find.textContaining('Prominence II(Minecraft 1.20.1'),
        findsOneWidget,
      );
    },
  );

  testWidgets('対象が 1 件も無い場合は一括翻訳へ進めない(012 AC-02 と整合)', (tester) async {
    await tester.runAsync(() async {
      await Directory(p.join(tempDir.path, 'config')).create(recursive: true);
    });

    await pumpPage(tester);

    final button = tester.widget<FilledButton>(
      find.byKey(const Key('openBatchTranslationButton')),
    );
    expect(button.onPressed, isNull);
  });
}
