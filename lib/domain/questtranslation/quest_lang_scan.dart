/// KubeJS lang / Better Quests 標準形式のディレクトリスキャンで共通利用する
/// ファイル名判定ロジック(feature-spec.md §7.1、§7.2)。
library;

/// 言語コード(例: `ja_jp` `zh_cn`)らしき `xx_xx` / `xxx_xxx` 形式の断片。
final _languageCodeFragment = RegExp(r'[a-zA-Z]{2,3}_[a-zA-Z]{2,3}');

/// 出力ファイル名パターン `{stem}.{languageCode}.json` に一致する、つまり
/// 既に翻訳済みの出力ファイルとみなせるかどうかを判定する。
///
/// KubeJS lang ディレクトリのスキャン時に「既に翻訳済みファイル名パターンは
/// 除外」する(feature-spec.md §7.1)ための判定に使う。`en_us.json` のような
/// 単一の言語コードのみからなるファイル名(ドット区切りの追加セグメントが
/// ない)は原文ファイルとみなし、対象外(= 翻訳済みではない)とする。
bool isAlreadyTranslatedLangFileName(String basename) {
  if (!basename.toLowerCase().endsWith('.json')) return false;

  final stem = basename.substring(0, basename.length - '.json'.length);
  final lastDot = stem.lastIndexOf('.');
  if (lastDot < 0) return false;

  final suffix = stem.substring(lastDot + 1);
  return _languageCodeFragment.hasMatch(suffix) &&
      RegExp('^${_languageCodeFragment.pattern}\$').hasMatch(suffix);
}

/// [basenames](ディレクトリ内の全ファイル名)から、翻訳元候補となる `.json`
/// ファイル名を抽出する(既に翻訳済みのファイル名パターンを除外し、
/// アルファベット順にソートする)。
List<String> listCandidateLangJsonBasenames(Iterable<String> basenames) {
  final candidates = basenames
      .where((name) => name.toLowerCase().endsWith('.json'))
      .where((name) => !isAlreadyTranslatedLangFileName(name))
      .toList();
  candidates.sort();
  return candidates;
}
