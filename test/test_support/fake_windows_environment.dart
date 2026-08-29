import 'package:villager_translator/infrastructure/minecraftinstance/windows_environment.dart';

/// テスト用の [WindowsEnvironment](011-launcher-instance-discovery.md §4)。
///
/// 実際のランチャーをインストールしていない環境および Windows 以外の CI 上でも、
/// 一時ディレクトリへ再現したフォルダ構造に対して検出処理を検証できるように、
/// `%APPDATA%` などを差し替える。
class FakeWindowsEnvironment implements WindowsEnvironment {
  const FakeWindowsEnvironment({
    this.appData,
    this.localAppData,
    this.userProfile,
    this.driveRoots = const [],
  });

  @override
  final String? appData;

  @override
  final String? localAppData;

  @override
  final String? userProfile;

  final List<String> driveRoots;

  @override
  Future<List<String>> fixedDriveRoots() async => driveRoots;
}
