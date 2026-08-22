/// 燈號判定結果
enum HealingStatus {
  good, // 🟢 良好 Healing
  stagnant, // 🟡 觀察 Stagnant
  deteriorating, // 🔴 惡化 Deteriorating
}

/// 單次拍照的組織比例分析結果（HSV 色彩門檻計算出的百分比）
class TissueComposition {
  final double redGranulationPct; // 紅色肉芽 %
  final double yellowSloughPct; // 黃色腐肉 %
  final double blackNecrosisPct; // 黑色壞死 %
  final double yellowGreenPusPct; // 黃綠膿液 %

  const TissueComposition({
    required this.redGranulationPct,
    required this.yellowSloughPct,
    required this.blackNecrosisPct,
    required this.yellowGreenPusPct,
  });
}

/// 單次傷口紀錄：對應 App 的一次拍照 + 分析結果
class WoundRecord {
  final String id;
  final String woundProfileId; // 屬於哪一個「傷口檔案」
  final DateTime capturedAt;
  final String imagePath; // 本機圖片路徑
  final double areaCm2; // 面積換算後的實際面積 (cm²)
  final double? areaChangePct; // 與上次紀錄比較的變化率
  final TissueComposition tissue;
  final HealingStatus status;
  final bool infectionSafetyNetTriggered; // 是否觸發「感染安全網」直接建議就醫

  const WoundRecord({
    required this.id,
    required this.woundProfileId,
    required this.capturedAt,
    required this.imagePath,
    required this.areaCm2,
    required this.tissue,
    required this.status,
    this.areaChangePct,
    this.infectionSafetyNetTriggered = false,
  });
}

/// 「傷口檔案」：使用者針對同一個傷口建立的追蹤基準
class WoundProfile {
  final String id;
  final String label; // 例如「左腳跟壓瘡」
  final DateTime createdAt;

  const WoundProfile({
    required this.id,
    required this.label,
    required this.createdAt,
  });
}
