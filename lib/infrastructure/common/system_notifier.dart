import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// 翻訳完了時の OS 通知を出すためのアダプター境界(feature-spec.md §10)。
///
/// [LlmAdapter] と同様、実装を差し替え可能にすることでウィジェットテストが
/// 実際の OS 通知を発火させずに済むようにする。
abstract class SystemNotifier {
  Future<void> initialize();

  Future<void> showTranslationCompleted({
    required String title,
    required String body,
  });
}

/// `flutter_local_notifications` を用いた Windows トースト通知の実装。
class FlutterLocalSystemNotifier implements SystemNotifier {
  FlutterLocalSystemNotifier({FlutterLocalNotificationsPlugin? plugin})
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;
  bool _initialized = false;

  static const _windowsAppUserModelId = 'VillagerTranslator.App';
  static const _windowsGuid = '{6F6E9B9B-6E9E-4E9B-9B6E-9B6E9B9B6E9B}';

  @override
  Future<void> initialize() async {
    if (_initialized) return;
    await _plugin.initialize(
      settings: const InitializationSettings(
        windows: WindowsInitializationSettings(
          appName: 'Villager Translator',
          appUserModelId: _windowsAppUserModelId,
          guid: _windowsGuid,
        ),
      ),
    );
    _initialized = true;
  }

  @override
  Future<void> showTranslationCompleted({
    required String title,
    required String body,
  }) async {
    await initialize();
    await _plugin.show(
      id: DateTime.now().millisecondsSinceEpoch.remainder(1 << 31),
      title: title,
      body: body,
    );
  }
}

/// 通知を発火させないテスト/既定用の実装。
class NoopSystemNotifier implements SystemNotifier {
  const NoopSystemNotifier();

  @override
  Future<void> initialize() async {}

  @override
  Future<void> showTranslationCompleted({
    required String title,
    required String body,
  }) async {}
}
