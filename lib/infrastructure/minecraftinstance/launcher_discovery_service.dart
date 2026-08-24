import '../../domain/minecraftinstance/instance_deduplicator.dart';
import '../../domain/minecraftinstance/minecraft_instance.dart';
import 'atlauncher_detector.dart';
import 'curseforge_launcher_detector.dart';
import 'launcher_detector.dart';
import 'manual_instance_detector.dart';
import 'modrinth_launcher_detector.dart';
import 'official_launcher_detector.dart';
import 'prism_launcher_detector.dart';
import 'windows_environment.dart';

/// 全 Detector を実行し、結果を重複排除・整列して返す
/// (011-launcher-instance-discovery.md §2、§11、§14)。
///
/// 検索は「標準パス → ランチャー設定 → 登録済み追加パス」に限定し、PC 内の
/// 全ドライブ再帰検索は既定では実行しない(AC-07)。詳細検索は
/// [searchInstancesDeeply] を明示的に呼んだときにのみ行う(§15.3)。
class LauncherDiscoveryService {
  LauncherDiscoveryService({
    required WindowsEnvironment environment,
    List<String> manualPaths = const [],
    List<LauncherDetector>? detectors,
  }) : detectors = detectors ?? buildDefaultDetectors(environment, manualPaths);

  /// 実行する Detector。重複排除のマージ規則(§11)に従い、ランチャー固有
  /// メタデータで確定判定できる Detector を先に並べる。
  final List<LauncherDetector> detectors;

  static List<LauncherDetector> buildDefaultDetectors(
    WindowsEnvironment environment,
    List<String> manualPaths,
  ) => [
    OfficialLauncherDetector(environment: environment),
    PrismLauncherDetector(
      environment: environment,
      additionalRootPaths: manualPaths,
    ),
    CurseForgeLauncherDetector(
      environment: environment,
      additionalRootPaths: manualPaths,
    ),
    ATLauncherDetector(
      environment: environment,
      additionalRootPaths: manualPaths,
    ),
    ModrinthLauncherDetector(
      environment: environment,
      additionalRootPaths: manualPaths,
    ),
    ManualInstanceDetector(paths: manualPaths),
  ];

  /// 全 Detector を実行して一覧を返す。
  ///
  /// 1 つの Detector が例外を投げても、そのランチャーの結果だけが空になり、
  /// 他ランチャーの検出は継続する(AC-20)。[onDetectorError] は失敗を
  /// ログへ残すためのフック。
  Future<List<MinecraftInstance>> discoverAll({
    void Function(LauncherDetector detector, Object error)? onDetectorError,
  }) async {
    final all = <MinecraftInstance>[];
    for (final detector in detectors) {
      try {
        all.addAll(await detector.discoverInstances());
      } catch (e) {
        onDetectorError?.call(detector, e);
      }
    }
    return sortInstancesForDisplay(deduplicateInstances(all));
  }
}
