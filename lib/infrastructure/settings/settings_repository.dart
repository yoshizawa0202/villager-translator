import 'dart:convert';
import 'dart:io';

import '../../domain/settings/app_settings.dart';

/// [AppSettings](API キーを除く)を JSON ファイルへ永続化する。
///
/// API キーはこのリポジトリの責務外であり、[ApiKeyStore] 経由で別途扱う
/// (feature-spec.md §15、受け入れ条件6)。
class SettingsRepository {
  const SettingsRepository(this.settingsFile);

  /// 設定を保存する JSON ファイル。
  final File settingsFile;

  /// アプリケーションサポートディレクトリ配下に `settings.json` を置く設定で構築する。
  factory SettingsRepository.forApplicationSupportDirectory(Directory dir) {
    return SettingsRepository(
      File('${dir.path}${Platform.pathSeparator}settings.json'),
    );
  }

  /// 設定を読み込む。ファイルが存在しない、または内容が壊れている場合は
  /// 例外を投げず [AppSettings.defaults] を返す。
  Future<AppSettings> load() async {
    if (!await settingsFile.exists()) {
      return AppSettings.defaults();
    }

    try {
      final text = await settingsFile.readAsString();
      final json = jsonDecode(text);
      if (json is! Map<String, dynamic>) {
        return AppSettings.defaults();
      }
      return AppSettings.fromJson(json);
    } catch (_) {
      return AppSettings.defaults();
    }
  }

  /// 設定を保存する。一時ファイルへ書き込んでからリネームすることで、
  /// 書き込み途中でのプロセス終了による設定ファイルの破損を防ぐ(原子的書き込み)。
  ///
  /// Windows では宛先が既に存在すると `rename` が失敗するため、既存ファイルを
  /// 一旦バックアップへ退避してからリネームし、成功後にバックアップを削除する。
  Future<void> save(AppSettings settings) async {
    await settingsFile.parent.create(recursive: true);

    final tempFile = File('${settingsFile.path}.tmp');
    final backupFile = File('${settingsFile.path}.bak');
    final encoder = const JsonEncoder.withIndent('  ');
    await tempFile.writeAsString(encoder.convert(settings.toJson()));

    if (await backupFile.exists()) {
      await backupFile.delete();
    }
    if (await settingsFile.exists()) {
      await settingsFile.rename(backupFile.path);
    }
    await tempFile.rename(settingsFile.path);
    if (await backupFile.exists()) {
      await backupFile.delete();
    }
  }
}
