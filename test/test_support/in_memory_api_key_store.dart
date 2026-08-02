import 'package:villager_translator/domain/llm/llm_provider.dart';
import 'package:villager_translator/infrastructure/settings/api_key_store.dart';

/// テスト専用の [ApiKeyStore] 実装。
///
/// `flutter_secure_storage` はプラットフォームチャンネル経由のため
/// `flutter test` では直接検証できない。この実装をテストの二重(fake)として使い、
/// [SettingsController] が API キーを常に [ApiKeyStore] 経由でのみ読み書きすることを
/// 検証する。
class InMemoryApiKeyStore implements ApiKeyStore {
  final Map<LlmProvider, String> _store = {};

  @override
  Future<String?> read(LlmProvider provider) async => _store[provider];

  @override
  Future<void> write(LlmProvider provider, String apiKey) async {
    _store[provider] = apiKey;
  }

  @override
  Future<void> delete(LlmProvider provider) async {
    _store.remove(provider);
  }
}
