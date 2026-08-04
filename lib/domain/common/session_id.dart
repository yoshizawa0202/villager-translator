/// セッションディレクトリ名として使うセッション ID を生成する
/// (`{プロファイル}/logs/localizer/{sessionId}/`、feature-spec.md §1.4)。
///
/// ISO8601 形式の日時文字列から、パスに使えない `:` `.` を `-` に置換する。
/// 文字列としての降順ソートが時系列の降順と一致するため、履歴一覧
/// ([HistoryRepository])のソートにもそのまま使える。
String defaultSessionId([DateTime? now]) =>
    (now ?? DateTime.now()).toIso8601String().replaceAll(RegExp(r'[:.]'), '-');
