import '../modtranslation/resource_pack_builder.dart';

/// Minecraft バージョンと `pack_format` の対応表 1 行分
/// (012-instance-batch-translation.md §11)。
class ResourcePackFormatRange {
  const ResourcePackFormatRange({
    required this.fromVersion,
    required this.toVersion,
    required this.packFormat,
  });

  /// この範囲の下限(この値を含む)。
  final String fromVersion;

  /// この範囲の上限(この値を含む)。
  final String toVersion;

  final int packFormat;
}

/// Minecraft バージョンと `pack_format` の対応表(§11)。
///
/// 各境界値は本仕様の「要検証項目」に含まれる。Minecraft 側の仕様変更に
/// 追随する保守対象であり、変更はこの表の 1 か所だけで完結する。
const List<ResourcePackFormatRange> kResourcePackFormatTable = [
  ResourcePackFormatRange(
    fromVersion: '1.6.1',
    toVersion: '1.8.9',
    packFormat: 1,
  ),
  ResourcePackFormatRange(
    fromVersion: '1.9',
    toVersion: '1.10.2',
    packFormat: 2,
  ),
  ResourcePackFormatRange(
    fromVersion: '1.11',
    toVersion: '1.12.2',
    packFormat: 3,
  ),
  ResourcePackFormatRange(
    fromVersion: '1.13',
    toVersion: '1.14.4',
    packFormat: 4,
  ),
  ResourcePackFormatRange(
    fromVersion: '1.15',
    toVersion: '1.16.1',
    packFormat: 5,
  ),
  ResourcePackFormatRange(
    fromVersion: '1.16.2',
    toVersion: '1.16.5',
    packFormat: 6,
  ),
  ResourcePackFormatRange(
    fromVersion: '1.17',
    toVersion: '1.17.1',
    packFormat: 7,
  ),
  ResourcePackFormatRange(
    fromVersion: '1.18',
    toVersion: '1.18.2',
    packFormat: 8,
  ),
  ResourcePackFormatRange(
    fromVersion: '1.19',
    toVersion: '1.19.2',
    packFormat: 9,
  ),
  ResourcePackFormatRange(
    fromVersion: '1.19.3',
    toVersion: '1.19.3',
    packFormat: 12,
  ),
  ResourcePackFormatRange(
    fromVersion: '1.19.4',
    toVersion: '1.19.4',
    packFormat: 13,
  ),
  ResourcePackFormatRange(
    fromVersion: '1.20',
    toVersion: '1.20.1',
    packFormat: 15,
  ),
  ResourcePackFormatRange(
    fromVersion: '1.20.2',
    toVersion: '1.20.2',
    packFormat: 18,
  ),
  ResourcePackFormatRange(
    fromVersion: '1.20.3',
    toVersion: '1.20.4',
    packFormat: 22,
  ),
  ResourcePackFormatRange(
    fromVersion: '1.20.5',
    toVersion: '1.20.6',
    packFormat: 32,
  ),
  ResourcePackFormatRange(
    fromVersion: '1.21',
    toVersion: '1.21.1',
    packFormat: 34,
  ),
];

/// [resolveResourcePackFormat] の結果(§11)。
class ResourcePackFormatResolution {
  const ResourcePackFormatResolution({
    required this.packFormat,
    required this.isEstimated,
    required this.isFallback,
  });

  final int packFormat;

  /// 対応表より新しいバージョンのため、対応表の最大エントリの値を推定として
  /// 使ったかどうか。`true` の場合は推定値である旨を画面に表示する(AC-14)。
  final bool isEstimated;

  /// バージョン不明・対応表より古いため、現行の既定値へフォールバックしたか。
  final bool isFallback;
}

/// Minecraft バージョン文字列から `pack_format` を求める(§11)。
///
/// フォールバック規則:
/// - バージョンを取得できない(`null` / 空 / `Unknown` / 解析不能)場合は
///   現行の既定値 [kResourcePackFormat] を使う
/// - 対応表の最も古いバージョンより前の場合も [kResourcePackFormat] を使う
/// - 対応表の最も新しいバージョンより後の場合は最大エントリの値を使い、
///   推定値である旨を返す
///
/// 不正なバージョン文字列でも例外を投げない(AC-14)。
ResourcePackFormatResolution resolveResourcePackFormat(
  String? minecraftVersion,
) {
  const fallback = ResourcePackFormatResolution(
    packFormat: kResourcePackFormat,
    isEstimated: false,
    isFallback: true,
  );

  final version = _parseVersion(minecraftVersion);
  if (version == null) return fallback;

  final first = kResourcePackFormatTable.first;
  if (_compare(version, _parseVersion(first.fromVersion)!) < 0) {
    return fallback;
  }

  final last = kResourcePackFormatTable.last;
  if (_compare(version, _parseVersion(last.toVersion)!) > 0) {
    return ResourcePackFormatResolution(
      packFormat: last.packFormat,
      isEstimated: true,
      isFallback: false,
    );
  }

  // 表は昇順のため、上限がバージョン以上になる最初の行が該当行。
  // 範囲の隙間に落ちた場合も、直近の下位の行の値を使う(表の更新漏れで
  // 例外にならないようにするため)。
  for (final range in kResourcePackFormatTable) {
    if (_compare(version, _parseVersion(range.toVersion)!) <= 0) {
      return ResourcePackFormatResolution(
        packFormat: range.packFormat,
        isEstimated: false,
        isFallback: false,
      );
    }
  }

  return fallback;
}

final RegExp _versionPattern = RegExp(r'^\d+(?:\.\d+)*');

/// `1.20.1` のような数値列を取り出す。`Unknown`、空文字、スナップショット
/// (`24w14a`)のように数値で始まらない値は `null`。
List<int>? _parseVersion(String? raw) {
  final trimmed = raw?.trim() ?? '';
  if (trimmed.isEmpty) return null;

  final match = _versionPattern.firstMatch(trimmed);
  if (match == null) return null;

  final parts = match
      .group(0)!
      .split('.')
      .map(int.tryParse)
      .whereType<int>()
      .toList();
  return parts.isEmpty ? null : parts;
}

int _compare(List<int> a, List<int> b) {
  final length = a.length > b.length ? a.length : b.length;
  for (var i = 0; i < length; i++) {
    final left = i < a.length ? a[i] : 0;
    final right = i < b.length ? b[i] : 0;
    if (left != right) return left.compareTo(right);
  }
  return 0;
}
