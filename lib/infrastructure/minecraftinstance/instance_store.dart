import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../domain/minecraftinstance/recent_instance.dart';

/// `instances.json` の内容(011-launcher-instance-discovery.md §15.5)。
class InstanceStoreData {
  const InstanceStoreData({
    this.manualPaths = const [],
    this.recentInstances = const [],
  });

  static const InstanceStoreData empty = InstanceStoreData();

  /// 利用者が手動追加したパス(§15.1)。次回起動時にも検索対象とする。
  final List<String> manualPaths;

  /// 最近使用したインスタンス(新しい順、最大 [kMaxRecentInstances] 件、§15.4)。
  final List<RecentInstance> recentInstances;

  InstanceStoreData copyWith({
    List<String>? manualPaths,
    List<RecentInstance>? recentInstances,
  }) => InstanceStoreData(
    manualPaths: manualPaths ?? this.manualPaths,
    recentInstances: recentInstances ?? this.recentInstances,
  );

  Map<String, dynamic> toJson() => {
    'manualPaths': manualPaths,
    'recentInstances': recentInstances.map((e) => e.toJson()).toList(),
  };

  factory InstanceStoreData.fromJson(Map<String, dynamic> json) {
    final rawPaths = json['manualPaths'];
    final rawRecents = json['recentInstances'];

    return InstanceStoreData(
      manualPaths: rawPaths is List
          ? rawPaths
                .whereType<String>()
                .where((path) => path.trim().isNotEmpty)
                .toList()
          : const [],
      recentInstances: rawRecents is List
          ? rawRecents
                .map(RecentInstance.tryFromJson)
                .whereType<RecentInstance>()
                .toList()
          : const [],
    );
  }
}

/// 手動追加パスと最近使用インスタンスを `instances.json` へ永続化する(§15.5)。
///
/// `settings.json`([SettingsRepository])とは別ファイルとする。更新契機も寿命も
/// 異なるため、責務と保存経路を分ける(設計判断「永続化先を settings.json と
/// 分ける」)。API キーはこのファイルにも保存しない。
class InstanceStore {
  const InstanceStore(this.file);

  /// プロファイル非依存のアプリケーションサポートディレクトリ配下に置く。
  factory InstanceStore.forApplicationSupportDirectory(Directory directory) =>
      InstanceStore(File(p.join(directory.path, 'instances.json')));

  final File file;

  /// 読み込む。ファイルが存在しない・壊れている場合は例外を投げず
  /// [InstanceStoreData.empty] を返す(AC-16、既存 [SettingsRepository] と同方針)。
  Future<InstanceStoreData> load() async {
    try {
      if (!await file.exists()) return InstanceStoreData.empty;
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map<String, dynamic>) return InstanceStoreData.empty;
      return InstanceStoreData.fromJson(decoded);
    } catch (_) {
      return InstanceStoreData.empty;
    }
  }

  Future<void> save(InstanceStoreData data) async {
    await file.parent.create(recursive: true);
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(data.toJson()),
    );
  }
}
