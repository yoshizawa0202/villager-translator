import 'dart:io';

/// 環境変数・ドライブ一覧の取得を注入可能にする抽象
/// (011-launcher-instance-discovery.md §4)。
///
/// 実際のランチャーをインストールしていない環境および Windows 以外の CI 上でも、
/// 一時ディレクトリへ再現したフォルダ構造に対して検出処理を検証できるようにする。
abstract class WindowsEnvironment {
  /// `%APPDATA%`(取得できない場合は `null`)。
  String? get appData;

  /// `%LOCALAPPDATA%`(取得できない場合は `null`)。
  String? get localAppData;

  /// `%USERPROFILE%`(取得できない場合は `null`)。
  String? get userProfile;

  /// 固定ドライブのルート一覧(`C:\`、`D:\` など)。詳細検索でのみ使う(§15.3)。
  Future<List<String>> fixedDriveRoots();
}

/// 実行環境の環境変数とドライブ一覧を返す実装。
class PlatformWindowsEnvironment implements WindowsEnvironment {
  const PlatformWindowsEnvironment();

  @override
  String? get appData => _nonEmpty(Platform.environment['APPDATA']);

  @override
  String? get localAppData => _nonEmpty(Platform.environment['LOCALAPPDATA']);

  @override
  String? get userProfile => _nonEmpty(Platform.environment['USERPROFILE']);

  /// `A:\`〜`Z:\` のうち実在するものを返す。
  ///
  /// Windows にはドライブ一覧を返す Dart の標準 API が無いため、ドライブレターを
  /// 総当たりで確認する(26 回の `exists()` で完了し、再帰探索は伴わない)。
  @override
  Future<List<String>> fixedDriveRoots() async {
    if (!Platform.isWindows) return const [];

    final roots = <String>[];
    for (
      var letter = 'A'.codeUnitAt(0);
      letter <= 'Z'.codeUnitAt(0);
      letter++
    ) {
      final root = '${String.fromCharCode(letter)}:${Platform.pathSeparator}';
      try {
        if (await Directory(root).exists()) roots.add(root);
      } catch (_) {
        // アクセスできないドライブは対象外とし、列挙全体は継続する(§15.3)。
      }
    }
    return roots;
  }

  static String? _nonEmpty(String? value) {
    if (value == null) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}
