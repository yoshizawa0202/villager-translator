/// 翻訳処理の協調的キャンセルを表すトークン(feature-spec.md §10)。
///
/// チャンクとチャンクの間で [isCancelled] を確認し、真であれば以降の処理を
/// 開始しない、という「協調的キャンセル」のためのフラグ。実行中の処理を
/// 強制中断する仕組みではない。
class CancellationToken {
  bool _isCancelled = false;

  bool get isCancelled => _isCancelled;

  void cancel() {
    _isCancelled = true;
  }
}
