import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:villager_translator/features/custom_file_translation/custom_file_translation_controller.dart';
import 'package:villager_translator/features/mod_translation/mod_translation_controller.dart';
import 'package:villager_translator/features/patchouli_translation/patchouli_translation_controller.dart';
import 'package:villager_translator/features/quest_translation/quest_translation_controller.dart';
import 'package:villager_translator/features/settings/settings_controller.dart';
import 'package:villager_translator/features/shell/main_shell_page.dart';
import 'package:villager_translator/features/shell/profile_directory_controller.dart';
import 'package:villager_translator/infrastructure/modtranslation/mod_translation_orchestrator.dart';

import '../../test_support/in_memory_api_key_store.dart';
import '../../test_support/in_memory_settings_repository.dart';

/// `scan()` を呼び出した瞬間に `scanning` 状態のまま停止させるための
/// フェイクオーケストレーター(タブロック(AC1)を安定して再現するため)。
class _HangingModOrchestrator extends ModTranslationOrchestrator {
  final Completer<ModScanResult> _completer = Completer<ModScanResult>();

  @override
  Future<ModScanResult> scan({
    required Directory profileDirectory,
    required String targetLanguageId,
    void Function(ModScanSkip skip)? onSkip,
  }) {
    return _completer.future;
  }
}

Future<SettingsController> _buildSettingsController() async {
  final controller = SettingsController(
    repository: InMemorySettingsRepository(),
    apiKeyStore: InMemoryApiKeyStore(),
  );
  await controller.load();
  return controller;
}

void main() {
  testWidgets('いずれかのタブがスキャン中の間は他タブへの切替が禁止される(受け入れ条件1)', (tester) async {
    final settingsController = await _buildSettingsController();
    final shared = ProfileDirectoryController();
    final modController = ModTranslationController(
      settingsController: settingsController,
      orchestrator: _HangingModOrchestrator(),
      profileDirectoryController: shared,
    );
    final questController = QuestTranslationController(
      settingsController: settingsController,
      profileDirectoryController: shared,
    );
    final patchouliController = PatchouliTranslationController(
      settingsController: settingsController,
      profileDirectoryController: shared,
    );
    final customFileController = CustomFileTranslationController(
      settingsController: settingsController,
      profileDirectoryController: shared,
    );

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<SettingsController>.value(
            value: settingsController,
          ),
        ],
        child: MaterialApp(
          home: MainShellPage(
            profileDirectoryController: shared,
            modController: modController,
            questController: questController,
            patchouliController: patchouliController,
            customFileController: customFileController,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // MOD タブをスキャン中状態のまま止める(directory を設定してから scan() を
    // await せず呼び出す。scan() は最初の await 到達前に同期的に scanning へ
    // 遷移するため、_HangingModOrchestrator により scanning のまま止まる)。
    modController.setProfileDirectoryPath('C:/dummy-profile');
    unawaited(modController.scan());
    await tester.pump();

    expect(find.text('スキャン中...'), findsOneWidget);

    // クエストタブをタップしても切り替わらないことを確認する
    // (IgnorePointer によりヒットテストされないこと自体が意図した挙動)。
    await tester.tap(find.byKey(const Key('questTab')), warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('profileDirectoryField')), findsOneWidget);
    expect(find.text('スキャン中...'), findsOneWidget);
  });

  testWidgets('MOD タブでプロファイルディレクトリを選択すると、他タブにも同じディレクトリが反映される(受け入れ条件2)', (
    tester,
  ) async {
    final settingsController = await _buildSettingsController();
    final shared = ProfileDirectoryController();
    final modController = ModTranslationController(
      settingsController: settingsController,
      profileDirectoryController: shared,
    );
    final questController = QuestTranslationController(
      settingsController: settingsController,
      profileDirectoryController: shared,
    );
    final patchouliController = PatchouliTranslationController(
      settingsController: settingsController,
      profileDirectoryController: shared,
    );
    final customFileController = CustomFileTranslationController(
      settingsController: settingsController,
      profileDirectoryController: shared,
    );

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<SettingsController>.value(
            value: settingsController,
          ),
        ],
        child: MaterialApp(
          home: MainShellPage(
            profileDirectoryController: shared,
            modController: modController,
            questController: questController,
            patchouliController: patchouliController,
            customFileController: customFileController,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    modController.setProfileDirectoryPath('C:/shared-profile');
    await tester.pump();

    expect(questController.profileDirectory!.path, 'C:/shared-profile');
    expect(patchouliController.profileDirectory!.path, 'C:/shared-profile');
    expect(customFileController.profileDirectory!.path, 'C:/shared-profile');
  });

  testWidgets('各タブの対象言語選択は互いに独立している(受け入れ条件3)', (tester) async {
    final settingsController = await _buildSettingsController();
    final shared = ProfileDirectoryController();
    final modController = ModTranslationController(
      settingsController: settingsController,
      profileDirectoryController: shared,
    );
    final questController = QuestTranslationController(
      settingsController: settingsController,
      profileDirectoryController: shared,
    );

    modController.setTargetLanguageId('fr_fr');
    questController.setTargetLanguageId('de_de');

    expect(modController.targetLanguageId, 'fr_fr');
    expect(questController.targetLanguageId, 'de_de');
  });

  testWidgets('翻訳(スキャン)実行中に設定画面を開くと、実行中である旨の注意書きが表示される(#9)', (
    tester,
  ) async {
    final settingsController = await _buildSettingsController();
    final shared = ProfileDirectoryController();
    final modController = ModTranslationController(
      settingsController: settingsController,
      orchestrator: _HangingModOrchestrator(),
      profileDirectoryController: shared,
    );
    final questController = QuestTranslationController(
      settingsController: settingsController,
      profileDirectoryController: shared,
    );
    final patchouliController = PatchouliTranslationController(
      settingsController: settingsController,
      profileDirectoryController: shared,
    );
    final customFileController = CustomFileTranslationController(
      settingsController: settingsController,
      profileDirectoryController: shared,
    );

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<SettingsController>.value(
            value: settingsController,
          ),
        ],
        child: MaterialApp(
          home: MainShellPage(
            profileDirectoryController: shared,
            modController: modController,
            questController: questController,
            patchouliController: patchouliController,
            customFileController: customFileController,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    modController.setProfileDirectoryPath('C:/dummy-profile');
    unawaited(modController.scan());
    await tester.pump();

    await tester.tap(find.byKey(const Key('openSettingsButton')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('translationRunningNotice')), findsOneWidget);
  });

  testWidgets('翻訳実行中でないときに設定画面を開いても注意書きは表示されない(#9)', (tester) async {
    final settingsController = await _buildSettingsController();
    final shared = ProfileDirectoryController();
    final modController = ModTranslationController(
      settingsController: settingsController,
      profileDirectoryController: shared,
    );
    final questController = QuestTranslationController(
      settingsController: settingsController,
      profileDirectoryController: shared,
    );
    final patchouliController = PatchouliTranslationController(
      settingsController: settingsController,
      profileDirectoryController: shared,
    );
    final customFileController = CustomFileTranslationController(
      settingsController: settingsController,
      profileDirectoryController: shared,
    );

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<SettingsController>.value(
            value: settingsController,
          ),
        ],
        child: MaterialApp(
          home: MainShellPage(
            profileDirectoryController: shared,
            modController: modController,
            questController: questController,
            patchouliController: patchouliController,
            customFileController: customFileController,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('openSettingsButton')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('translationRunningNotice')), findsNothing);
  });
}
