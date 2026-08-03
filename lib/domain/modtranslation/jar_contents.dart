import 'dart:convert';

/// JAR(zip)内のエントリ一覧を、パス(`/` 区切り)→ 生バイト列で表す。
///
/// 実際の zip 展開は infrastructure 層([JarReader] 等)が担い、domain 層は
/// この単純な Map に対する純粋関数としてスキャン・パース処理を行う
/// (テスト容易性のため実ファイル I/O から切り離す)。
typedef JarContents = Map<String, List<int>>;

/// [path] のエントリを UTF-8 テキストとして読む。存在しなければ `null`。
///
/// 不正なバイト列は置換文字へ変換し(`allowMalformed`)、テキスト抽出自体は
/// 失敗させない。内容の妥当性検証は呼び出し側([lang_codec.dart] 等)が行う。
String? readJarText(JarContents jar, String path) {
  final bytes = jar[path];
  if (bytes == null) return null;
  return utf8.decode(bytes, allowMalformed: true);
}
