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

/// 參考 PUSH Tool 概念設計的決策樹，整合面積變化 + 組織比例，
/// 疊加感染安全網規則，輸出燈號建議。對應簡報 Step 6。
///
/// ⚠️ 這是自行設計的規則，非官方醫療量表，展示時需明確說明限制。
class DecisionService {
  // TODO: 這個絕對面積門檻要跟指導老師/資料確認合理值，目前先佔位
  static const double _absoluteAreaAlertThresholdCm2 = 25.0;

  DecisionResult decide({
    required double areaCm2,
    required double? areaChangePct,
    required TissueComposition tissue,
  }) {
    // 安全網規則：不論組織比例結果如何，面積超過門檻直接建議就醫
    if (areaCm2 > _absoluteAreaAlertThresholdCm2 ||
        tissue.yellowGreenPusPct > 0) {
      return const DecisionResult(
        status: HealingStatus.deteriorating,
        infectionSafetyNetTriggered: true,
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

    // 🟡 觀察：黃色腐肉 25%~50%，或面積連續停滯（±5% 內）
    // TODO: 「連續兩週停滯」需要比對前兩次紀錄，目前先用單次資料簡化判斷
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

  const DecisionResult({
    required this.status,
    required this.advice,
    this.infectionSafetyNetTriggered = false,
  });
}
