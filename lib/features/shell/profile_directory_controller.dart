import 'dart:io';

import 'package:flutter/foundation.dart';

/// 4タブ(MOD/クエスト/ガイドブック/カスタムファイル)で共有するプロファイル
/// ディレクトリの選択状態(feature-spec.md §3.2、008-progress-log-history.md
/// 受け入れ条件2)。
///
/// いずれかのタブでディレクトリを選択すると、この共有インスタンスを購読する
/// 全タブへ同じ変更が伝播する。
class ProfileDirectoryController extends ChangeNotifier {
  Directory? _profileDirectory;
  Directory? get profileDirectory => _profileDirectory;

  void setPath(String path) {
    _profileDirectory = Directory(path);
    notifyListeners();
  }

  void clear() {
    _profileDirectory = null;
    notifyListeners();
  }
}
