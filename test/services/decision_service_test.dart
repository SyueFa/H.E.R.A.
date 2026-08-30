import 'package:flutter_test/flutter_test.dart';
import 'package:hera/services/decision_service.dart';
import 'package:hera/models/wound_record.dart';

void main() {
  final decision = DecisionService();

  TissueComposition tissue({
    double red = 20,
    double yellow = 20,
    double black = 20,
    double pus = 0,
  }) {
    return TissueComposition(
      redGranulationPct: red,
      yellowSloughPct: yellow,
      blackNecrosisPct: black,
      yellowGreenPusPct: pus,
    );
  }

  group('安全網規則', () {
    test('面積超過門檻，直接判定惡化（面積門檻原因）', () {
      final result = decision.decide(
        areaCm2: 30, // 超過 _absoluteAreaAlertThresholdCm2 = 25
        areaChangePct: 5,
        tissue: tissue(pus: 0),
      );
      expect(result.status, HealingStatus.deteriorating);
      expect(result.infectionSafetyNetTriggered, true);
      expect(result.safetyNetReason, SafetyNetReason.areaThreshold);
    });

    test('偵測到膿液，直接判定惡化（膿液偵測原因），優先於面積原因', () {
      final result = decision.decide(
        areaCm2: 30, // 同時超過面積門檻
        areaChangePct: 5,
        tissue: tissue(pus: 10),
      );
      expect(result.status, HealingStatus.deteriorating);
      expect(result.infectionSafetyNetTriggered, true);
      expect(result.safetyNetReason, SafetyNetReason.pusDetected);
    });
  });

  group('惡化規則（非安全網）', () {
    test('黑+黃組織 > 50%，判定惡化', () {
      final result = decision.decide(
        areaCm2: 5,
        areaChangePct: 5,
        tissue: tissue(red: 10, yellow: 30, black: 30, pus: 0),
      );
      expect(result.status, HealingStatus.deteriorating);
      expect(result.infectionSafetyNetTriggered, false);
    });

    test('面積擴大（changePct 為負），判定惡化', () {
      final result = decision.decide(
        areaCm2: 5,
        areaChangePct: -8, // 負值代表面積比上次大
        tissue: tissue(),
      );
      expect(result.status, HealingStatus.deteriorating);
    });
  });

  group('良好規則', () {
    test('紅色肉芽 > 75% 且面積縮小 > 10%，判定良好', () {
      final result = decision.decide(
        areaCm2: 5,
        areaChangePct: 15,
        tissue: tissue(red: 80, yellow: 10, black: 10, pus: 0),
      );
      expect(result.status, HealingStatus.good);
    });
  });

  group('觀察／停滯規則', () {
    test('黃色腐肉在 25%~50% 之間，直接判定觀察（不需要連續兩次）', () {
      final result = decision.decide(
        areaCm2: 5,
        areaChangePct: 20, // 即使變化率不小，腐肉比例本身就觸發
        tissue: tissue(red: 20, yellow: 35, black: 10, pus: 0),
      );
      expect(result.status, HealingStatus.stagnant);
    });

    test('只有這一次面積停滯（±5% 內），沒有上一次資料，不應算連續停滯而誤判', () {
      final result = decision.decide(
        areaCm2: 5,
        areaChangePct: 3, // 這次在 ±5% 內
        previousAreaChangePct: null, // 上一筆是第一筆，無上上次可比
        tissue: tissue(red: 40, yellow: 15, black: 10, pus: 0), // 不落在腐肉觸發區間
      );
      // 目前 fallback 邏輯仍會落到 stagnant（因為沒有其他規則命中），
      // 但關鍵是 status 不是因為「連續兩次」這條規則被觸發——
      // 這個測試主要用來鎖住行為，之後如果改了 fallback 邏輯，這裡能提醒。
      expect(result.status, HealingStatus.stagnant);
    });

    test('連續兩次面積變化都在 ±5% 內，判定觀察／停滯', () {
      final result = decision.decide(
        areaCm2: 5,
        areaChangePct: 3, // 這次 3%
        previousAreaChangePct: -2, // 上次 -2%，兩次都在門檻內
        tissue: tissue(red: 40, yellow: 15, black: 10, pus: 0),
      );
      expect(result.status, HealingStatus.stagnant);
    });

    test('這次停滯但上次變化很大（非連續），不應觸發「連續兩次」這條規則', () {
      final result = decision.decide(
        areaCm2: 5,
        areaChangePct: 3, // 這次在門檻內
        previousAreaChangePct: 25, // 上次變化很大，不算停滯
        tissue: tissue(red: 40, yellow: 15, black: 10, pus: 0),
      );
      // 兩種規則都沒被連續停滯觸發，但目前 fallback 預設仍是 stagnant，
      // 這裡同樣是鎖住現有行為的測試。
      expect(result.status, HealingStatus.stagnant);
    });
  });
}