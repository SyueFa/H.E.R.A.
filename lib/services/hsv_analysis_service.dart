import 'package:image/image.dart' as img;
import '../models/wound_record.dart';

/// 純數學運算，不吃 AI 算力：在 YOLO 分割出的傷口遮罩範圍內，
/// 用 HSV 色彩門檻計算組織比例。對應簡報 Step 5。
///
/// HSV 門檻值（角度制／百分比制，之後要用真實資料集微調）：
///   紅色肉芽 Granulation : 鮮紅色系
///   黃色腐肉 Slough      : 黃 / 白
///   黑色壞死 Necrosis    : 黑 / 深棕
///   黃綠膿液 Pus         : 黃綠色系（感染跡象）
class HsvAnalysisService {
  // TODO: 這些門檻值要用 WoundTissue / DFUTissue 資料集實際標註來校正，
  // 目前先放常見的粗略範圍，之後在資料前處理階段一併驗證。
  static const _redHueRange = (min: 340, max: 20); // 跨 0 度，鮮紅
  static const _yellowHueRange = (min: 40, max: 65);
  static const _yellowGreenHueRange = (min: 65, max: 90);
  static const _blackValueMax = 0.25; // HSV 的 V（明度）低於此值視為黑/深棕

  /// [image] 為原始照片，[maskPixels] 為 YOLO 分割出的傷口遮罩座標集合
  /// （只分析遮罩內的像素，遮罩外的背景不計入）。
  TissueComposition analyze({
    required img.Image image,
    required List<(int x, int y)> maskPixels,
  }) {
    if (maskPixels.isEmpty) {
      return const TissueComposition(
        redGranulationPct: 0,
        yellowSloughPct: 0,
        blackNecrosisPct: 0,
        yellowGreenPusPct: 0,
      );
    }

    int redCount = 0, yellowCount = 0, blackCount = 0, yellowGreenCount = 0;

    for (final (x, y) in maskPixels) {
      final pixel = image.getPixel(x, y);
      final hsv = _rgbToHsv(pixel.r.toInt(), pixel.g.toInt(), pixel.b.toInt());

      if (hsv.v <= _blackValueMax) {
        blackCount++;
      } else if (_inHueRange(hsv.h, _redHueRange.min, _redHueRange.max)) {
        redCount++;
      } else if (_inHueRange(hsv.h, _yellowHueRange.min, _yellowHueRange.max)) {
        yellowCount++;
      } else if (_inHueRange(
          hsv.h, _yellowGreenHueRange.min, _yellowGreenHueRange.max)) {
        yellowGreenCount++;
      }
    }

    final total = maskPixels.length;
    return TissueComposition(
      redGranulationPct: redCount / total * 100,
      yellowSloughPct: yellowCount / total * 100,
      blackNecrosisPct: blackCount / total * 100,
      yellowGreenPusPct: yellowGreenCount / total * 100,
    );
  }

  bool _inHueRange(double h, num min, num max) {
    if (min <= max) return h >= min && h <= max;
    return h >= min || h <= max; // 跨 0 度（例如紅色 340°~20°）
  }

  ({double h, double s, double v}) _rgbToHsv(int r, int g, int b) {
    final rf = r / 255.0, gf = g / 255.0, bf = b / 255.0;
    final maxC = [rf, gf, bf].reduce((a, b) => a > b ? a : b);
    final minC = [rf, gf, bf].reduce((a, b) => a < b ? a : b);
    final delta = maxC - minC;

    double h = 0;
    if (delta != 0) {
      if (maxC == rf) {
        h = 60 * (((gf - bf) / delta) % 6);
      } else if (maxC == gf) {
        h = 60 * (((bf - rf) / delta) + 2);
      } else {
        h = 60 * (((rf - gf) / delta) + 4);
      }
    }
    if (h < 0) h += 360;

    final s = maxC == 0 ? 0.0 : delta / maxC;
    final v = maxC;

    return (h: h, s: s, v: v);
  }
}
