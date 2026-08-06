import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:villager_translator/domain/common/cancellation_token.dart';
import 'package:villager_translator/domain/common/translation_progress.dart';
import 'package:villager_translator/domain/llm/llm_adapter.dart';
import 'package:villager_translator/domain/llm/llm_adapter_config.dart';
import 'package:villager_translator/domain/llm/llm_provider.dart';
import 'package:villager_translator/domain/settings/app_settings.dart';
import 'package:villager_translator/features/mod_translation/mod_translation_controller.dart';
import 'package:villager_translator/features/mod_translation/mod_translation_page.dart';
import 'package:villager_translator/features/settings/settings_controller.dart';
import 'package:villager_translator/infrastructure/llm/llm_adapter_factory.dart';
import 'package:villager_translator/infrastructure/llm/mock_llm_adapter.dart';
import 'package:villager_translator/infrastructure/modtranslation/mod_translation_orchestrator.dart';

import '../../test_support/fake_jar_builder.dart';
import '../../test_support/in_memory_api_key_store.dart';
import '../../test_support/in_memory_settings_repository.dart';

class _FakeAdapterFactory implements LlmAdapterFactory {
  @override
  LlmAdapter create(LlmProvider provider, LlmAdapterConfig config) =>
      const MockLlmAdapter();
}

/// `translateAndPack()` を呼び出した瞬間に進捗コールバックだけ発火させたうえで
/// 停止させるフェイクオーケストレーター(進捗パネル表示(Issue #7)を安定して
/// 再現するため、`main_shell_page_test.dart` の `_HangingModOrchestrator` と
/// 同様の方針)。
class _ProgressHangingOrchestrator extends ModTranslationOrchestrator {
  _ProgressHangingOrchestrator({required this.adapterFactory})
    : super(adapterFactory: adapterFactory);

  final LlmAdapterFactory adapterFactory;
  final Completer<ModTranslateAndPackResult> _completer = Completer();

  @override
  Future<ModTranslateAndPackResult> translateAndPack({
    required Directory profileDirectory,
    required List<ModScanEntry> selectedEntries,
    required String targetLanguageId,
    required String targetLanguageDisplayName,
    required AppSettings settings,
    required String apiKey,
    required String sessionId,
    CancellationToken? cancellationToken,
    SingleFileProgressCallback? onSingleFileProgress,
    OverallProgressCallback? onOverallProgress,
    ItemChunkResultCallback? onChunkResult,
    CurrentItemCallback? onItemStarted,
  }) {
    onItemStarted?.call('Mod A');
    onOverallProgress?.call(
      const OverallProgress(completedItems: 0, totalItems: 2),
    );
    onSingleFileProgress?.call(
      const ChunkProgress(completedChunks: 1, totalChunks: 3),
    );
    return _completer.future;
  }
}

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp(
      'mod_translation_page_test_',
    );
    await writeFakeJar(File(p.join(tempDir.path, 'mods', 'moda.jar')), {
      'fabric.mod.json': '{"id": "moda", "name": "Mod A", "version": "1.0"}',
      'assets/moda/lang/en_us.json': '{"item.a": "Item A"}',
    });
    await writeFakeJar(File(p.join(tempDir.path, 'mods', 'zmod.jar')), {
      'fabric.mod.json': '{"id": "zmod", "name": "Zmod", "version": "1.0"}',
      'assets/zmod/lang/en_us.json': '{"item.z": "Item Z"}',
    });
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  Future<ModTranslationController> pumpPage(WidgetTester tester) async {
    final settingsController = SettingsController(
      repository: InMemorySettingsRepository(),
      apiKeyStore: InMemoryApiKeyStore(),
    );
    await settingsController.load();
    await settingsController.setApiKey(LlmProvider.openai, 'test-key');

    final modController = ModTranslationController(
      settingsController: settingsController,
      orchestrator: ModTranslationOrchestrator(
        adapterFactory: _FakeAdapterFactory(),
      ),
    );

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<SettingsController>.value(
            value: settingsController,
          ),
        ],
        child: MaterialApp(home: ModTranslationPage(controller: modController)),
      ),
    );
    await tester.pumpAndSettle();

    return modController;
  }

  testWidgets('未選択→スキャン完了→翻訳完了の状態遷移と、テーブルのチェックボックス・検索が機能する', (tester) async {
    final controller = await pumpPage(tester);

    expect(find.text('未選択'), findsOneWidget);

    // ディレクトリ未選択の間はスキャンボタンが無効。
    final scanButtonBefore = tester.widget<ElevatedButton>(
      find.byKey(const Key('scanButton')),
    );
    expect(scanButtonBefore.onPressed, isNull);

    await tester.enterText(
      find.byKey(const Key('profileDirectoryField')),
      tempDir.path,
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(controller.profileDirectory!.path, tempDir.path);

    // スキャンボタンが有効になったことを確認したうえで、実ファイル I/O
    // (dart:io)を伴うためコントローラーを直接呼び出して結果を検証する
    // (fake-async 環境の pump は実 I/O の完了を待てないため)。
    final scanButtonAfter = tester.widget<ElevatedButton>(
      find.byKey(const Key('scanButton')),
    );
    expect(scanButtonAfter.onPressed, isNotNull);

    await tester.runAsync(() => controller.scan());
    await tester.pumpAndSettle();

    expect(find.text('スキャン完了'), findsOneWidget);
    expect(find.byKey(const Key('modRow_moda.jar')), findsOneWidget);
    expect(find.byKey(const Key('modRow_zmod.jar')), findsOneWidget);
    expect(controller.selectedModIds, {'moda', 'zmod'});

    // 部分一致検索: "zmod" で絞り込む。
    await tester.enterText(find.byKey(const Key('searchField')), 'zmod');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('modRow_moda.jar')), findsNothing);
    expect(find.byKey(const Key('modRow_zmod.jar')), findsOneWidget);

    await tester.enterText(find.byKey(const Key('searchField')), '');
    await tester.pumpAndSettle();

    // チェックボックス列: zmod の選択を解除する。
    await tester.tap(find.byKey(const Key('modRow_zmod.jar')));
    await tester.pumpAndSettle();
    expect(controller.selectedModIds, {'moda'});

    final translateButtonAfter = tester.widget<ElevatedButton>(
      find.byKey(const Key('translateButton')),
    );
    expect(translateButtonAfter.onPressed, isNotNull);

    await tester.runAsync(() => controller.translate());
    await tester.pumpAndSettle();

    expect(find.text('完了'), findsOneWidget);
    expect(find.byKey(const Key('translationResultSummary')), findsOneWidget);
    expect(controller.lastResult!.translationResult.translatedModIds, ['moda']);
    // 完了後は進捗パネルを表示しない(feature-spec.md §10、Issue #7)。
    expect(find.byKey(const Key('translationProgressPanel')), findsNothing);
  });

  testWidgets('翻訳中はプログレスバーと現在処理中の対象名が表示される(受け入れ条件4a,4b、Issue #7)', (
    tester,
  ) async {
    final settingsController = SettingsController(
      repository: InMemorySettingsRepository(),
      apiKeyStore: InMemoryApiKeyStore(),
    );
    await settingsController.load();
    await settingsController.setApiKey(LlmProvider.openai, 'test-key');

    final adapterFactory = _FakeAdapterFactory();
    final modController = ModTranslationController(
      settingsController: settingsController,
      orchestrator: _ProgressHangingOrchestrator(
        adapterFactory: adapterFactory,
      ),
    );

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<SettingsController>.value(
            value: settingsController,
          ),
        ],
        child: MaterialApp(home: ModTranslationPage(controller: modController)),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('profileDirectoryField')),
      tempDir.path,
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    await tester.runAsync(() => modController.scan());
    await tester.pumpAndSettle();

    // translate() を await せずに呼び出す。セッションログ開始が実ファイル
    // I/O(dart:io)を伴うため runAsync 内で実イベントループを進めたうえで、
    // _ProgressHangingOrchestrator が進捗コールバックを発火させて停止する
    // (main_shell_page_test.dart の _HangingModOrchestrator と同様の方針)。
    await tester.runAsync(() async {
      unawaited(modController.translate());
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pump();

    expect(find.byKey(const Key('translationProgressPanel')), findsOneWidget);
    expect(find.text('翻訳中: Mod A'), findsOneWidget);
    expect(find.byKey(const Key('overallProgressBar')), findsOneWidget);
    expect(find.text('0 / 2 件完了 (0%)'), findsOneWidget);
    expect(find.byKey(const Key('singleFileProgressBar')), findsOneWidget);

    // オーケストレーターを永久に停止させたままにすると、開いたままの
    // セッションログファイルハンドルが tempDir の削除(tearDown)を
    // Windows 上でブロックするため、明示的にセッションを終了させる。
    await tester.runAsync(() => modController.sessionLogger.endSession());
  });

  testWidgets('同一 MOD ID を持つ JAR が複数あってもテーブルが例外なく描画される', (tester) async {
    // 同じ MOD ID を宣言する JAR が mods/ に複数存在するケース(例: 新旧バージョンの
    // 残存)。行の Key を MOD ID だけで組み立てると Table の重複 Key 検証に
    // 引っかかってクラッシュするため、JAR ごとに一意な jarRelativePath で
    // 一意性を担保できているかを確認する。
    late Directory duplicateIdDir;
    await tester.runAsync(() async {
      duplicateIdDir = await Directory.systemTemp.createTemp(
        'mod_translation_page_test_dup_',
      );
      await writeFakeJar(
        File(p.join(duplicateIdDir.path, 'mods', 'dupmod-1.0.jar')),
        {
          'fabric.mod.json':
              '{"id": "dupmod", "name": "Dup Mod", "version": "1.0"}',
          'assets/dupmod/lang/en_us.json': '{"item.a": "Item A"}',
        },
      );
      await writeFakeJar(
        File(p.join(duplicateIdDir.path, 'mods', 'dupmod-1.1.jar')),
        {
          'fabric.mod.json':
              '{"id": "dupmod", "name": "Dup Mod", "version": "1.1"}',
          'assets/dupmod/lang/en_us.json': '{"item.a": "Item A v2"}',
        },
      );
    });
    addTearDown(() async {
      if (await duplicateIdDir.exists()) {
        await duplicateIdDir.delete(recursive: true);
      }
    });

    final controller = await pumpPage(tester);

    await tester.enterText(
      find.byKey(const Key('profileDirectoryField')),
      duplicateIdDir.path,
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    await tester.runAsync(() => controller.scan());
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('スキャン完了'), findsOneWidget);
    expect(find.byKey(const Key('modRow_dupmod-1.0.jar')), findsOneWidget);
    expect(find.byKey(const Key('modRow_dupmod-1.1.jar')), findsOneWidget);
  });
}
