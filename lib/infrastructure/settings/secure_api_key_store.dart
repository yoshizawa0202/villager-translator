import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../domain/llm/llm_provider.dart';
import 'api_key_store.dart';

/// Windows の資格情報マネージャー(DPAPI)を利用した [ApiKeyStore] 実装
/// (feature-spec.md §15)。
class SecureApiKeyStore implements ApiKeyStore {
  SecureApiKeyStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  String _keyFor(LlmProvider provider) => 'llm_api_key_${provider.id}';

  @override
  Future<String?> read(LlmProvider provider) =>
      _storage.read(key: _keyFor(provider));

  @override
  Future<void> write(LlmProvider provider, String apiKey) =>
      _storage.write(key: _keyFor(provider), value: apiKey);

  @override
  Future<void> delete(LlmProvider provider) =>
      _storage.delete(key: _keyFor(provider));
}
