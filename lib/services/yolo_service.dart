import 'dart:io';
import 'package:ultralytics_yolo/yolo.dart';

/// 負責載入 YOLOv8n-seg 模型並執行「傷口邊界分割」推論。
/// 模型只做單類別分割（傷口 vs 背景），對應簡報 Step 3。
class YoloService {
  YOLO? _model;
  bool get isLoaded => _model != null;

  // TODO: 換成組員訓練完、INT8 量化、匯出後的實際檔名
  // Android: assets/models/wound_seg_int8.tflite
  // iOS: assets/models/wound_seg.mlpackage
  static const _modelPath = 'assets/models/wound_seg_int8.tflite';

  Future<void> loadModel() async {
    _model = YOLO(
      modelPath: _modelPath,
      task: YOLOTask.segment,
    );
    await _model!.loadModel();
  }

  /// 對單張拍攝好的照片執行分割，回傳傷口遮罩（mask）與邊界框。
  /// 之後把 mask 交給 HsvAnalysisService 做組織分析、交給
  /// AreaCalculationService 做面積換算。
  ///
  /// 注意：ultralytics_yolo 0.1.x 版本的 predict() 吃的是圖片的
  /// Uint8List bytes（不是檔案路徑），回傳的是 Map<String, dynamic>
  /// （常見 key 有 'boxes'、'masks'、'annotatedImage' 等，實際結構
  /// 要接上真實模型後印出來確認一次）。這跟套件較新版本改成
  /// List<YOLOResult> 的介面不同，鎖定版本時要注意這點。
  Future<Map<String, dynamic>> segmentWoundBoundary(File imageFile) async {
    if (_model == null) {
      throw StateError('模型尚未載入，請先呼叫 loadModel()');
    }
    final bytes = await imageFile.readAsBytes();
    final results = await _model!.predict(bytes);
    return results;
    // TODO: 實機測試 — 官方套件在不同 YOLO 版本間曾出現推論結果跑掉的
    // 相容性問題，訓練完模型後務必先跟 Python 端輸出比對，確認一致再上線。
    // TODO: 拿到真實模型後，先 print(results.keys) 確認這個 Map 實際
    // 包含哪些欄位，再寫解析遮罩座標的邏輯。
  }

  void dispose() {
    _model?.dispose();
    _model = null;
  }
}
