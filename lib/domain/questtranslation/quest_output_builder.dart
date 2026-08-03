import 'package:path/path.dart' as p;

import '../translation/lang_codec.dart';
import 'quest_scan_entry.dart';
import 'quest_translation_service.dart';
import 'snbt_extractor.dart';

/// クエスト相対パス(`/` 区切り)を扱うための POSIX スタイルの [p.Context]。
///
/// プロファイルディレクトリ以下の仮想的な相対パスは常に `/` 区切りで統一し、
/// 実ファイルシステムへの書き込み(プラットフォーム区切り文字への変換)は
/// infrastructure 層の責務とする。
final _relativePath = p.posix;

/// リソースパック/クエスト出力ファイル1件(プロファイルディレクトリからの
/// 相対パスと内容)。
class QuestOutputFile {
  const QuestOutputFile({required this.relativePath, required this.content});

  final String relativePath;
  final String content;
}

/// [output] から書き出すファイル一式を組み立てる(feature-spec.md §7.1、§7.2)。
///
/// - KubeJS lang: `kubejs/assets/kubejs/lang/{lang}.json` と
///   `kubejs/assets/ftbquests/lang/{lang}.json` の両方に同一内容を書き出す
///   (設計判断: 旧 `docs/spec.md` の意図どおり両方に出力する、受け入れ条件2)。
/// - SNBT: 元ファイルへ直接上書きする内容を、同じ相対パスで返す
///   (言語サフィックス付きの別ファイルは作らない、受け入れ条件5)。
/// - Better Quests 標準: 同ディレクトリの `{basename}.{lang}.json`
///   (受け入れ条件7)。
/// - Better Quests 直接: 同ディレクトリの `DefaultQuests.{lang}.lang`
///   (受け入れ条件8)。
///
/// JSON/LANG 出力のキーは [encodeLang] によりソートされる(受け入れ条件9)。
List<QuestOutputFile> buildQuestOutputFiles(
  QuestTranslationOutput output,
  String targetLanguageId,
) {
  final entry = output.entry;

  switch (entry.format) {
    case QuestFormat.ftbQuestsKubejsLang:
      final json = encodeLangJson(output.entries);
      return [
        QuestOutputFile(
          relativePath: 'kubejs/assets/kubejs/lang/$targetLanguageId.json',
          content: json,
        ),
        QuestOutputFile(
          relativePath: 'kubejs/assets/ftbquests/lang/$targetLanguageId.json',
          content: json,
        ),
      ];

    case QuestFormat.ftbQuestsSnbt:
      final content = reconstructSnbt(
        entry.snbtOriginalContent ?? '',
        entry.snbtSpans ?? const [],
        output.entries,
      );
      return [
        QuestOutputFile(relativePath: entry.relativePath, content: content),
      ];

    case QuestFormat.betterQuestingStandard:
      final dir = _relativePath.dirname(entry.relativePath);
      final stem = _relativePath.basenameWithoutExtension(
        entry.relativePath,
      );
      return [
        QuestOutputFile(
          relativePath: _relativePath.join(dir, '$stem.$targetLanguageId.json'),
          content: encodeLangJson(output.entries),
        ),
      ];

    case QuestFormat.betterQuestingDirect:
      final dir = _relativePath.dirname(entry.relativePath);
      return [
        QuestOutputFile(
          relativePath: _relativePath.join(
            dir,
            'DefaultQuests.$targetLanguageId.lang',
          ),
          content: encodeLangFile(output.entries),
        ),
      ];
  }
}

/// 差分更新・スキップ判定で確認する既存翻訳ファイルの相対パス
/// (feature-spec.md §7.3)。
///
/// SNBT は既存翻訳の判定が不能なため常に `null` を返す(受け入れ条件11)。
String? existingTranslationCheckPath(
  QuestScanEntry entry,
  String targetLanguageId,
) {
  switch (entry.format) {
    case QuestFormat.ftbQuestsSnbt:
      return null;
    case QuestFormat.ftbQuestsKubejsLang:
      return 'kubejs/assets/kubejs/lang/$targetLanguageId.json';
    case QuestFormat.betterQuestingStandard:
      final dir = _relativePath.dirname(entry.relativePath);
      final stem = _relativePath.basenameWithoutExtension(
        entry.relativePath,
      );
      return _relativePath.join(dir, '$stem.$targetLanguageId.json');
    case QuestFormat.betterQuestingDirect:
      final dir = _relativePath.dirname(entry.relativePath);
      return _relativePath.join(dir, 'DefaultQuests.$targetLanguageId.lang');
  }
}
