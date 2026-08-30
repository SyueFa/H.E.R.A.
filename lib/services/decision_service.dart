import '../models/wound_record.dart';

/// 面積換算：像素面積 → 實際 cm²（依比例尺）
class AreaCalculationService {
  /// [pixelArea] 傷口遮罩的像素總數
  /// [scalePixelLength] 比例尺貼紙在照片中的像素長度
  /// [scaleRealLengthCm] 比例尺貼紙的實際長度（cm）
  double pixelAreaToCm2({
    required int pixelArea,
    required double scalePixelLength,
    required double scaleRealLengthCm,
  }) {
    final cmPerPixel = scaleRealLengthCm / scalePixelLength;
    return pixelArea * cmPerPixel * cmPerPixel;
  }

  /// 變化率 = (上次面積 - 本次面積) / 上次面積 × 100%
  /// 正值代表縮小（變好），負值代表擴大（變差）
  double? areaChangePct({required double? previousAreaCm2, required double currentAreaCm2}) {
    if (previousAreaCm2 == null || previousAreaCm2 == 0) return null;
    return (previousAreaCm2 - currentAreaCm2) / previousAreaCm2 * 100;
  }
}

/// 感染安全網觸發的具體原因，用來讓 UI 區分「保守性面積警示」
/// 跟「偵測到膿液」這兩種可信度不同的觸發來源。
enum SafetyNetReason { areaThreshold, pusDetected }

/// 參考 PUSH Tool 概念設計的決策樹，整合面積變化 + 組織比例，
/// 疊加感染安全網規則，輸出燈號建議。對應簡報 Step 6。
///
/// ⚠️ 這是自行設計的規則，非官方醫療量表，展示時需明確說明限制。
class DecisionService {
  // TODO: 這個絕對面積門檻要跟指導老師/資料確認合理值，目前先佔位
  static const double _absoluteAreaAlertThresholdCm2 = 25.0;

  // 判定「停滯」的變化率門檻：變化幅度在 ±5% 內視為沒有明顯進展或惡化
  static const double _stagnantChangePctThreshold = 5.0;

  DecisionResult decide({
    required double areaCm2,
    required double? areaChangePct,
    // 上一筆紀錄「自己的」areaChangePct（也就是上一筆相對於它前一筆的變化率）。
    // WoundRecord 儲存時本來就會存這個值，不需要額外查兩筆歷史紀錄，
    // 直接把上一筆的這個欄位傳進來即可判斷「連續兩次」是否都停滯。
    double? previousAreaChangePct,
    required TissueComposition tissue,
  }) {
    final pusDetected = tissue.yellowGreenPusPct > 0;
    final areaExceeded = areaCm2 > _absoluteAreaAlertThresholdCm2;

    // 安全網規則：不論組織比例結果如何，面積超過門檻或偵測到膿液，
    // 直接建議就醫。膿液是組織分析真的偵測到的訊號，優先視為該原因；
    // 純粹只是面積超標（沒有膿液）才算是保守性安全網。
    if (areaExceeded || pusDetected) {
      final reason = pusDetected ? SafetyNetReason.pusDetected : SafetyNetReason.areaThreshold;
      return DecisionResult(
        status: HealingStatus.deteriorating,
        infectionSafetyNetTriggered: true,
        safetyNetReason: reason,
        advice: '感染風險高或傷口面積過大，建議尋求醫師清創評估',
      );
    }

    // 🔴 惡化：黑色壞死 + 黃色腐肉 > 50%，或面積擴大
    final necroticSloughSum = tissue.blackNecrosisPct + tissue.yellowSloughPct;
    if (necroticSloughSum > 50 || (areaChangePct != null && areaChangePct < 0)) {
      return const DecisionResult(
        status: HealingStatus.deteriorating,
        advice: '感染風險高，建議尋求醫師清創',
      );
    }

    // 🟢 良好：紅色肉芽 > 75% 且面積比上週縮小 > 10%
    if (tissue.redGranulationPct > 75 &&
        areaChangePct != null &&
        areaChangePct > 10) {
      return const DecisionResult(
        status: HealingStatus.good,
        advice: '組織修復正常，持續目前護理',
      );
    }

    // 🟡 觀察：黃色腐肉 25%~50%，或「連續兩次」面積變化都在 ±5% 內
    // （本次 vs 上次、上次 vs 上上次都要停滯，單次落在 ±5% 內不算數）。
    final sloughInStagnantRange =
        tissue.yellowSloughPct >= 25 && tissue.yellowSloughPct <= 50;

    final currentStagnant =
        areaChangePct != null && areaChangePct.abs() <= _stagnantChangePctThreshold;
    final previousStagnant = previousAreaChangePct != null &&
        previousAreaChangePct.abs() <= _stagnantChangePctThreshold;
    final consecutiveStagnant = currentStagnant && previousStagnant;

    if (sloughInStagnantRange || consecutiveStagnant) {
      return const DecisionResult(
        status: HealingStatus.stagnant,
        advice: '復原停滯，加強滲出液控制與清潔',
      );
    }

    // 其餘未落入任一明確規則的情況（例如組織比例中等、面積變化不上不下、
    // 但還沒連續兩次停滯），先保守歸類為觀察，等資料更多再細分。
    return const DecisionResult(
      status: HealingStatus.stagnant,
      advice: '復原停滯，加強滲出液控制與清潔',
    );
  }
}

class DecisionResult {
  final HealingStatus status;
  final String advice;
  final bool infectionSafetyNetTriggered;
  final SafetyNetReason? safetyNetReason;

  const DecisionResult({
    required this.status,
    required this.advice,
    this.infectionSafetyNetTriggered = false,
    this.safetyNetReason,
  });
}