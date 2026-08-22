import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'wound_record.dart';

/// 集中管理的設計 token，對應線框稿定下的視覺語言：
/// - 主色藍 + 醫療綠，卡片式列表
/// - 燈號用固定色（好/觀察/惡化）
/// - 量測數字一律用等寬字體，呈現「儀器讀數」感
///
/// TronClass 實際色票確認後，只要改這個檔案裡的顏色常數即可，
/// 不用動任何畫面的 layout 程式碼。
class AppTheme {
  static const Color ink = Color(0xFF0F2438);
  static const Color inkSoft = Color(0xFF5A7186);
  static const Color line = Color(0xFFE1E8F0);
  static const Color bg = Color(0xFFF4F7FB);
  static const Color card = Color(0xFFFFFFFF);

  static const Color blue = Color(0xFF1257C4);
  static const Color bluePale = Color(0xFFE8F0FE);
  static const Color teal = Color(0xFF1E9E8C);
  static const Color tealPale = Color(0xFFE3F6F2);

  static const Color good = Color(0xFF2FA86B);
  static const Color goodBg = Color(0xFFE6F7EE);
  static const Color warn = Color(0xFFE0A430);
  static const Color warnBg = Color(0xFFFDF3E1);
  static const Color bad = Color(0xFFE14B3F);
  static const Color badBg = Color(0xFFFCEAE8);

  /// 量測數字（面積 cm²、百分比、天數）一律用這個等寬字體
  static TextStyle mono({
    double fontSize = 14,
    FontWeight fontWeight = FontWeight.w600,
    Color? color,
  }) =>
      GoogleFonts.jetBrainsMono(
        fontSize: fontSize,
        fontWeight: fontWeight,
        color: color ?? ink,
      );

  static ThemeData theme() {
    return ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: bg,
      colorScheme: ColorScheme.fromSeed(seedColor: blue, primary: blue),
      textTheme: GoogleFonts.notoSansTcTextTheme(),
      appBarTheme: const AppBarTheme(
        backgroundColor: card,
        foregroundColor: ink,
        elevation: 0,
        surfaceTintColor: card,
      ),
      cardTheme: CardThemeData(
        color: card,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: line),
        ),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: blue,
        foregroundColor: Colors.white,
      ),
    );
  }
}

/// 燈號對應的顏色 + emoji + 中文標籤，畫面上多處共用，集中在這裡維護。
class StatusStyle {
  final Color color;
  final Color bg;
  final String emoji;
  final String label;

  const StatusStyle({
    required this.color,
    required this.bg,
    required this.emoji,
    required this.label,
  });

  static StatusStyle of(HealingStatus status) {
    return switch (status) {
      HealingStatus.good => const StatusStyle(
          color: AppTheme.good, bg: AppTheme.goodBg, emoji: '🟢', label: '良好'),
      HealingStatus.stagnant => const StatusStyle(
          color: AppTheme.warn, bg: AppTheme.warnBg, emoji: '🟡', label: '觀察'),
      HealingStatus.deteriorating => const StatusStyle(
          color: AppTheme.bad, bg: AppTheme.badBg, emoji: '🔴', label: '惡化'),
    };
  }
}
