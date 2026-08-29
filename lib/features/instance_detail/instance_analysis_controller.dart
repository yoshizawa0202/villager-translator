import 'package:flutter/foundation.dart';

import '../../domain/common/cancellation_token.dart';
import '../../domain/minecraftinstance/instance_analysis.dart';
import '../../domain/minecraftinstance/minecraft_instance.dart';
import '../../domain/settings/supported_language.dart';
import '../../infrastructure/minecraftinstance/instance_analyzer.dart';

/// 自動解析の状態遷移(011-launcher-instance-discovery.md §16)。
enum InstanceAnalysisState { idle, analyzing, analyzed, failed }

/// インスタンス選択後の自動解析の状態を保持する(§16)。
///
/// スキャンには既存のスキャナ([InstanceAnalyzer])をそのまま再利用し、新しい
/// スキャン処理は追加しない。翻訳済み・未翻訳の内訳は各スキャン結果が既に持つ
/// `hasExistingTranslation` から集計する([InstanceAnalysis])。
class InstanceAnalysisController extends ChangeNotifier {
  InstanceAnalysisController({
    required MinecraftInstance instance,
    InstanceAnalyzer analyzer = const InstanceAnalyzer(),
    String? targetLanguageId,
  }) : _instance = instance,
       _analyzer = analyzer,
       _targetLanguageId = targetLanguageId ?? kDefaultLanguages.first.id;

  final InstanceAnalyzer _analyzer;

  MinecraftInstance _instance;

  /// 解析対象。解析後は多段フォールバック(§12 の第3段)で補完された値になる。
  MinecraftInstance get instance => _instance;

  String _targetLanguageId;
  String get targetLanguageId => _targetLanguageId;

  InstanceAnalysisState _state = InstanceAnalysisState.idle;
  InstanceAnalysisState get state => _state;

  InstanceAnalysis? _analysis;
  InstanceAnalysis? get analysis => _analysis;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  /// 解析中の段階(進捗表示用、§16)。
  InstanceAnalysisStage? _stage;
  InstanceAnalysisStage? get stage => _stage;

  CancellationToken? _cancellationToken;
  bool get isCancelling => _cancellationToken?.isCancelled ?? false;

  /// 対象言語を変更する。既存翻訳の判定結果が変わるため、解析をやり直す。
  Future<void> setTargetLanguageId(String languageId) async {
    if (_targetLanguageId == languageId) return;
    _targetLanguageId = languageId;
    notifyListeners();
    await analyze();
  }

  /// 既存の 3 スキャナで翻訳対象を解析する(§16)。
  ///
  /// 解析中に対象インスタンスが削除されていた場合は、日本語のエラーメッセージを
  /// 設定して [InstanceAnalysisState.failed] にする(AC-21)。
  Future<void> analyze() async {
    final token = CancellationToken();
    _cancellationToken = token;
    _state = InstanceAnalysisState.analyzing;
    _errorMessage = null;
    _stage = null;
    notifyListeners();

    try {
      final result = await _analyzer.analyze(
        instance: _instance,
        targetLanguageId: _targetLanguageId,
        cancellationToken: token,
        onStageStarted: (stage) {
          _stage = stage;
          notifyListeners();
        },
      );
      _analysis = result;
      _instance = result.instance;
      _state = InstanceAnalysisState.analyzed;
    } on InstanceNotFoundException catch (e) {
      _errorMessage = e.toString();
      _state = InstanceAnalysisState.failed;
    } catch (e) {
      _errorMessage = 'インスタンスの解析に失敗しました: $e';
      _state = InstanceAnalysisState.failed;
    } finally {
      _cancellationToken = null;
      _stage = null;
    }
    notifyListeners();
  }

  /// 実行中の解析をキャンセルする(協調的キャンセル、§16)。
  void cancel() {
    _cancellationToken?.cancel();
    notifyListeners();
  }
}
