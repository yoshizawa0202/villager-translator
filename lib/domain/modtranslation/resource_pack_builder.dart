import 'dart:convert';

import '../translation/lang_codec.dart';
import 'mod_translation_service.dart';

/// `pack.mcmeta` の `pack_format`(feature-spec.md §6.2)。
const int kResourcePackFormat = 9;

/// `pack.mcmeta`(format 9)の内容を生成する。
String buildPackMcmeta({String description = 'Villager Translator'}) {
  final json = {
    'pack': {'pack_format': kResourcePackFormat, 'description': description},
  };
  return const JsonEncoder.withIndent('  ').convert(json);
}

/// 翻訳結果([outputs])から、1つのリソースパックへ書き出すファイル一式
/// (相対パス → 内容)を組み立てる(feature-spec.md §6.2)。
///
/// 1回の実行で選択した全 MOD を1つのリソースパックにまとめる(MOD ごとに
/// 別パックは作らない、受け入れ条件12)。各 lang ファイルのキーは
/// [encodeLang] によりソートされる(受け入れ条件13)。
Map<String, String> buildResourcePackFiles({
  required List<ModTranslationOutput> outputs,
  required String targetLanguageId,
  String packDescription = 'Villager Translator',
}) {
  final files = <String, String>{
    'pack.mcmeta': buildPackMcmeta(description: packDescription),
  };

  for (final output in outputs) {
    final path =
        'assets/${output.modId}/lang/$targetLanguageId.${output.format.extension}';
    files[path] = encodeLang(output.entries, output.format);
  }

  return files;
}
