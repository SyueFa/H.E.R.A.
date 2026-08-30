import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import '../models/wound_record.dart';
import '../models/app_theme.dart';
import '../services/decision_service.dart';
import '../services/storage_service.dart';
import '../services/yolo_service.dart';
import '../services/hsv_analysis_service.dart';

/// 拍照 → 分割 → 組織分析 → 面積換算 → 決策判定 → 燈號建議
/// 完整走一次簡報六步驟資料流。
///
/// 設計原則：即使真實 YOLO 模型還沒訓練好、assets/models/ 是空的，
/// 這條流程也「一定會走完」——沒有模型時自動退回示範資料，
/// 讓 UI/UX（分析中 → 燈號結果 → 存進歷史紀錄）可以先驗證，
/// 不用等模型到手才能測試畫面。之後模型真的接上，只要
/// _runSegmentation() 裡的真實推論不再拋錯，就會自動改用真實結果。
class CameraCaptureScreen extends StatefulWidget {
  final WoundProfile profile;
  final StorageService storage;

  const CameraCaptureScreen({
    super.key,
    required this.profile,
    required this.storage,
  });

  @override
  State<CameraCaptureScreen> createState() => _CameraCaptureScreenState();
}

class _CameraCaptureScreenState extends State<CameraCaptureScreen> {
  CameraController? _controller;
  final YoloService _yolo = YoloService();

  // 目前 _analyzeImage() 裡真實模型分支還在 throw UnimplementedError，
  // 尚未走到呼叫 _hsv.analyze() 那一步，所以這個欄位暫時沒被使用。
  // 等模型輸出解析邏輯接上、能真的餵給 HSV 分析後就會用到，先保留。
  // ignore: unused_field
  final HsvAnalysisService _hsv = HsvAnalysisService();
  final AreaCalculationService _area = AreaCalculationService();
  final DecisionService _decision = DecisionService();

  bool _isProcessing = false;
  bool _modelLoaded = false;
  // 桌機模擬器沒有實體鏡頭時，CameraX/availableCameras() 會直接拋錯。
  // 這裡接住這個情況，讓畫面不會卡死，改顯示「模擬拍照」按鈕，
  // 讓沒有 Webcam 的開發機也能測試後面的分析／燈號／資料庫流程。
  bool _cameraUnavailable = false;
  String? _cameraErrorMessage;

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  Future<void> _initCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        throw CameraException('noCamerasAvailable', '沒有偵測到任何相機裝置');
      }
      final backCamera = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      _controller = CameraController(backCamera, ResolutionPreset.high);
      await _controller!.initialize();
    } catch (e) {
      // 常見於桌機模擬器（沒有實體 Webcam，或沒有正確設定虛擬相機）。
      // 手機實機測試不會遇到這個分支，因為手機一定有相機。
      _cameraUnavailable = true;
      _cameraErrorMessage = e.toString();
    }

    // 模型檔案還沒放進 assets/models/ 之前，loadModel() 一定會失敗，
    // 這裡刻意接住，讓相機還是能正常打開、拍照，只是分析階段會
    // 退回示範資料。等組員的 .tflite 檔案放進去，這裡會自動成功。
    try {
      await _yolo.loadModel();
      _modelLoaded = true;
    } catch (_) {
      _modelLoaded = false;
    }

    if (mounted) setState(() {});
  }

  Future<void> _captureAndAnalyze() async {
    if (_controller == null || !_controller!.value.isInitialized) return;
    setState(() => _isProcessing = true);
    try {
      final file = await _controller!.takePicture();
      await _runAnalysisPipeline(imagePath: file.path);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('分析失敗：$e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  /// 沒有實體相機（例如桌機模擬器）時的替代路徑：跳過真的拍照，
  /// 直接用一個佔位路徑走完「分析 → 決策 → 存檔 → 顯示結果」流程。
  /// 因為目前分析邏輯本來就是走示範資料 fallback，不看照片實際內容，
  /// 所以這條路徑產生的紀錄跟真的拍照產生的紀錄，在資料庫裡是等價的，
  /// 適合用來驗證燈號判定、連續停滯邏輯、趨勢圖等跟相機無關的功能。
  Future<void> _simulateAndAnalyze() async {
    setState(() => _isProcessing = true);
    try {
      final placeholderPath =
          'mock_no_camera_${DateTime.now().microsecondsSinceEpoch}.jpg';
      await _runAnalysisPipeline(imagePath: placeholderPath);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('分析失敗：$e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  /// 拍照／模擬拍照共用的後續流程：分析 → 決策 → 存檔 → 顯示結果彈窗。
  Future<void> _runAnalysisPipeline({required String imagePath}) async {
    final previous = await widget.storage.getLatestRecord(widget.profile.id);

    final (double areaCm2, TissueComposition tissue) = await _analyzeImage(
      imagePath.startsWith('mock_') ? null : File(imagePath),
      previousAreaCm2: previous?.areaCm2,
    );

    final changePct = _area.areaChangePct(
      previousAreaCm2: previous?.areaCm2,
      currentAreaCm2: areaCm2,
    );

    final result = _decision.decide(
      areaCm2: areaCm2,
      areaChangePct: changePct,
      // previous 這筆紀錄自己的 areaChangePct，就是「上次 vs 上上次」的
      // 變化率，跟這次算出的 changePct 合在一起，才能判斷連續兩次是否
      // 都落在停滯門檻內。
      previousAreaChangePct: previous?.areaChangePct,
      tissue: tissue,
    );

    final record = WoundRecord(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      woundProfileId: widget.profile.id,
      capturedAt: DateTime.now(),
      imagePath: imagePath,
      areaCm2: areaCm2,
      areaChangePct: changePct,
      tissue: tissue,
      status: result.status,
      infectionSafetyNetTriggered: result.infectionSafetyNetTriggered,
    );
    await widget.storage.saveRecord(record);

    if (mounted) {
      _showResultDialog(
        result,
        areaCm2: areaCm2,
        tissue: tissue,
        usedRealModel: _modelLoaded,
      );
    }
  }

  /// 真正的模型接上後，這裡會走 YOLO 分割 + HSV 分析；
  /// 模型還沒到手（或載入/推論失敗）時，退回一組隨機但合理的
  /// 示範資料，讓後面的決策樹、彈窗、資料庫、趨勢圖都能真實跑一遍。
  Future<(double, TissueComposition)> _analyzeImage(
    File? imageFile, {
    double? previousAreaCm2,
  }) async {
    if (_modelLoaded && imageFile != null) {
      try {
        // Step 2: 邊界分割
        // ignore: unused_local_variable
        final segResults = await _yolo.segmentWoundBoundary(imageFile);
        // TODO: segResults 是 Map<String, dynamic>，實際欄位要等真實模型
        // 接上後印出來確認（常見會有 'boxes'、'masks' 之類的 key），
        // 再從中解析遮罩座標，交給 HsvAnalysisService.analyze() 計算組織比例，
        // 交給 AreaCalculationService.pixelAreaToCm2() 換算面積。
        // 目前先讓它自然拋錯（欄位還沒解析），落到下面的 catch。
        throw UnimplementedError('真實模型輸出解析邏輯尚未串接');
      } catch (_) {
        // 真實推論失敗（模型輸出格式還沒解析、或模型本身有問題），
        // 一樣退回示範資料，不讓使用者卡住。
      }
    }
    return _mockAnalysis(previousAreaCm2: previousAreaCm2);
  }

  /// 示範資料：面積在前次基礎上做小幅隨機變動，組織比例隨機生成但
  /// 四色合計 100%，讓決策樹、趨勢圖、燈號都有東西可以測試。
  (double, TissueComposition) _mockAnalysis({double? previousAreaCm2}) {
    final rand = Random();
    final base = previousAreaCm2 ?? (3 + rand.nextDouble() * 4);
    final areaCm2 = (base * (0.85 + rand.nextDouble() * 0.3)).clamp(0.5, 30.0);

    final red = 20 + rand.nextDouble() * 50;
    final yellow = rand.nextDouble() * (100 - red) * 0.6;
    final black = rand.nextDouble() * (100 - red - yellow) * 0.5;
    final yellowGreen = 100 - red - yellow - black;

    return (
      areaCm2,
      TissueComposition(
        redGranulationPct: red,
        yellowSloughPct: yellow,
        blackNecrosisPct: black,
        yellowGreenPusPct: yellowGreen.clamp(0, 100),
      ),
    );
  }

  void _showResultDialog(
    DecisionResult result, {
    required double areaCm2,
    required TissueComposition tissue,
    required bool usedRealModel,
  }) {
    final style = StatusStyle.of(result.status);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(color: style.bg, shape: BoxShape.circle),
              child: Center(child: Text(style.emoji, style: const TextStyle(fontSize: 28))),
            ),
            const SizedBox(height: 12),
            Text(
              style.label,
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: style.color),
            ),
            const SizedBox(height: 6),
            Text(
              result.advice,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, color: AppTheme.inkSoft, height: 1.5),
            ),

            // 安全網觸發時，額外說明這次警示的可信度來源
            // （面積門檻＝保守性規則 vs 膿液偵測＝組織訊號），
            // 避免使用者把兩種不同可信度的紅色警示混為一談。
            if (result.infectionSafetyNetTriggered && result.safetyNetReason != null) ...[
              const SizedBox(height: 10),
              _SafetyNetNotice(reason: result.safetyNetReason!),
            ],

            // 對應數據，讓使用者（或未來的醫師）能回頭核對是哪個
            // 訊號觸發的判斷。
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: AppTheme.line)),
              ),
              child: Column(
                children: [
                  _dataRow('面積', '${areaCm2.toStringAsFixed(1)} cm²'),
                  if (result.safetyNetReason == SafetyNetReason.pusDetected)
                    _dataRow(
                      '黃綠膿液比例',
                      '${tissue.yellowGreenPusPct.toStringAsFixed(0)}%',
                      danger: true,
                    )
                  else
                    _dataRow(
                      '黑+黃組織比例',
                      '${(tissue.blackNecrosisPct + tissue.yellowSloughPct).toStringAsFixed(0)}%',
                    ),
                ],
              ),
            ),

            if (!usedRealModel) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: AppTheme.bg,
                  borderRadius: BorderRadius.circular(100),
                ),
                child: Text(
                  '⚠️ 示範資料（模型尚未接上）',
                  style: AppTheme.mono(fontSize: 10, color: AppTheme.inkSoft),
                ),
              ),
            ],
          ],
        ),
        actions: [
          Center(
            child: FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppTheme.blue),
              onPressed: () => Navigator.pop(context),
              child: const Text('確定'),
            ),
          ),
        ],
        actionsAlignment: MainAxisAlignment.center,
      ),
    );
  }

  Widget _dataRow(String label, String value, {bool danger = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 12, color: AppTheme.inkSoft)),
          Text(
            value,
            style: AppTheme.mono(fontSize: 12, color: danger ? AppTheme.bad : AppTheme.ink),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _controller?.dispose();
    _yolo.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;

    // 相機初始化失敗（常見於桌機模擬器沒有 Webcam）：
    // 顯示說明文字＋「模擬拍照」按鈕，讓其餘功能還是能測試。
    if (_cameraUnavailable) {
      return Scaffold(
        appBar: AppBar(title: Text('拍攝：${widget.profile.label}')),
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.videocam_off, size: 48, color: AppTheme.inkSoft),
                const SizedBox(height: 12),
                const Text(
                  '偵測不到相機\n（開發測試用：可能是模擬器沒有接 Webcam，\n或這台電腦沒有鏡頭）',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: AppTheme.inkSoft, height: 1.6),
                ),
                if (_cameraErrorMessage != null) ...[
                  const SizedBox(height: 6),
                  // 完整錯誤訊息可能很長，限制高度並可獨立捲動查看，
                  // 避免把整個畫面撐爆造成 overflow。
                  Container(
                    constraints: const BoxConstraints(maxHeight: 120),
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppTheme.bg,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: SingleChildScrollView(
                      child: Text(
                        _cameraErrorMessage!,
                        style: AppTheme.mono(fontSize: 9, color: AppTheme.inkSoft),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: AppTheme.blue),
                  onPressed: _isProcessing ? null : _simulateAndAnalyze,
                  icon: _isProcessing
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.science_outlined),
                  label: Text(_isProcessing ? '分析中...' : '模擬拍照並判讀（測試用）'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text('拍攝：${widget.profile.label}')),
      body: controller == null || !controller.value.isInitialized
          ? const Center(child: CircularProgressIndicator())
          : Stack(
              children: [
                CameraPreview(controller),
                // TODO: 拍攝引導 — 角度/距離提示 + 比例尺貼紙辨識疊加層，
                // 確保跨週影像可比對（簡報「拍攝引導」功能）
                const _ScaleGuideOverlay(),
              ],
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _isProcessing ? null : _captureAndAnalyze,
        icon: _isProcessing
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.camera),
        label: Text(_isProcessing ? '分析中...' : '拍照並判讀'),
      ),
    );
  }
}

/// 安全網觸發原因說明條：面積門檻用琥珀色（保守性警示），
/// 膿液偵測用紅色（真實組織訊號），讓使用者一眼分辨可信度來源。
class _SafetyNetNotice extends StatelessWidget {
  final SafetyNetReason reason;
  const _SafetyNetNotice({required this.reason});

  @override
  Widget build(BuildContext context) {
    final isPus = reason == SafetyNetReason.pusDetected;
    final color = isPus ? AppTheme.bad : AppTheme.warn;
    final bg = isPus ? AppTheme.badBg : AppTheme.warnBg;
    final title = isPus ? '由組織分析判定' : '本次由安全網門檻觸發';
    final detail = isPus
        ? '偵測到黃綠膿液，判定為惡化警示。'
        : '傷口絕對面積超過設定門檻，非組織比例分析判定，屬保守性警示。';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: color)),
          const SizedBox(height: 2),
          Text(detail, style: const TextStyle(fontSize: 11, color: AppTheme.inkSoft, height: 1.4)),
        ],
      ),
    );
  }
}

/// 拍攝引導疊加層：文字提示 + 置中的比例尺對齊框。
/// 之後要接上真的比例尺辨識，這個框目前只是視覺引導，不會自動偵測。
class _ScaleGuideOverlay extends StatelessWidget {
  const _ScaleGuideOverlay();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 10),
          margin: const EdgeInsets.only(top: 16),
          child: const Center(
            child: Text(
              '請將比例尺貼紙置於框內',
              style: TextStyle(
                color: Colors.white,
                backgroundColor: Colors.black45,
                fontSize: 13,
              ),
            ),
          ),
        ),
        Expanded(
          child: Center(
            child: Container(
              width: 180,
              height: 180,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white70, width: 2),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Stack(
                children: [
                  _cornerMark(Alignment.topLeft),
                  _cornerMark(Alignment.topRight),
                  _cornerMark(Alignment.bottomLeft),
                  _cornerMark(Alignment.bottomRight),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _cornerMark(Alignment alignment) {
    return Align(
      alignment: alignment,
      child: Container(
        width: 22,
        height: 22,
        decoration: BoxDecoration(
          border: Border(
            top: alignment.y < 0 ? const BorderSide(color: Colors.tealAccent, width: 3) : BorderSide.none,
            bottom: alignment.y > 0 ? const BorderSide(color: Colors.tealAccent, width: 3) : BorderSide.none,
            left: alignment.x < 0 ? const BorderSide(color: Colors.tealAccent, width: 3) : BorderSide.none,
            right: alignment.x > 0 ? const BorderSide(color: Colors.tealAccent, width: 3) : BorderSide.none,
          ),
        ),
      ),
    );
  }
}