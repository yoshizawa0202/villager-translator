import 'package:flutter_test/flutter_test.dart';
import 'package:villager_translator/infrastructure/common/system_notifier.dart';

void main() {
  test('NoopSystemNotifier は例外を起こさず何もしない', () async {
    const notifier = NoopSystemNotifier();
    await notifier.initialize();
    await notifier.showTranslationCompleted(title: 'title', body: 'body');
  });
}
