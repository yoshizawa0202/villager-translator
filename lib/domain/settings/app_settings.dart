import 'llm_settings.dart';
import 'translation_settings.dart';

/// テーマ切替の選択状態(feature-spec.md §3.1、008-progress-log-history.md)。
///
/// Flutter の `ThemeMode` と値集合を合わせているが、`lib/domain` は
/// Flutter に依存しないため独自定義する(UI 層で相互変換する)。
enum AppThemeMode { system, light, dark }

/// アプリケーション設定全体(API キーを除く)。
///
/// API キーは構造的にこのクラスへ含まれない。設定ファイル(JSON)に書き出しても
/// API キーが漏れることはない(feature-spec.md §15、受け入れ条件6)。
class AppSettings {
  const AppSettings({
    required this.llm,
    required this.translation,
    this.themeMode = AppThemeMode.system,
  });

  final LlmSettings llm;
  final TranslationSettings translation;

  /// テーマ切替(feature-spec.md §3.1、008-progress-log-history.md)。
  final AppThemeMode themeMode;

  /// 現行の設定ファイルスキーマバージョン。
  static const int schemaVersion = 1;

  static AppSettings defaults() => AppSettings(
    llm: LlmSettings.defaults(),
    translation: TranslationSettings.defaults(),
  );

  AppSettings copyWith({
    LlmSettings? llm,
    TranslationSettings? translation,
    AppThemeMode? themeMode,
  }) {
    return AppSettings(
      llm: llm ?? this.llm,
      translation: translation ?? this.translation,
      themeMode: themeMode ?? this.themeMode,
    );
  }

  Map<String, dynamic> toJson() => {
    'schemaVersion': schemaVersion,
    'llm': llm.toJson(),
    'translation': translation.toJson(),
    'themeMode': themeMode.name,
  };

  /// JSON から復元する。ファイル全体が壊れている場合の扱いは呼び出し側
  /// ([lib/infrastructure/settings/settings_repository.dart] 参照)に委ね、
  /// ここでは各セクションが欠損・不正な場合にそのセクションのみ既定値へ
  /// フォールバックする。
  factory AppSettings.fromJson(Map<String, dynamic> json) {
    final fallback = AppSettings.defaults();

    final llmJson = json['llm'];
    final translationJson = json['translation'];
    final themeModeName = json['themeMode'];

    return AppSettings(
      llm: llmJson is Map<String, dynamic>
          ? LlmSettings.fromJson(llmJson)
          : fallback.llm,
      translation: translationJson is Map<String, dynamic>
          ? TranslationSettings.fromJson(translationJson)
          : fallback.translation,
      themeMode: themeModeName is String
          ? _themeModeFromName(themeModeName) ?? fallback.themeMode
          : fallback.themeMode,
    );
  }
}

AppThemeMode? _themeModeFromName(String name) {
  for (final mode in AppThemeMode.values) {
    if (mode.name == name) return mode;
  }
  return null;
}
