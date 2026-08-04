import '../../domain/llm/llm_provider.dart';

/// プロバイダーごとの API キーを保管する抽象境界。
///
/// 実装は暗号化されたセキュアストレージを使用しなければならない
/// (feature-spec.md §15)。[SettingsController] は API キーの読み書きを常に
/// この抽象経由でのみ行い、[AppSettings] には含めない。
abstract class ApiKeyStore {
  Future<String?> read(LlmProvider provider);
  Future<void> write(LlmProvider provider, String apiKey);
  Future<void> delete(LlmProvider provider);
}
