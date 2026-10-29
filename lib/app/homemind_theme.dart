import 'package:flutter/material.dart';

import '../core/product_groups.dart';

class HomeMindTheme {
  static const String fontFamily = 'BeVietnamPro';

  // Primary brand colors
  static const Color primary = Color(0xFF2FBF71);
  static const Color primaryDark = Color(0xFF1B8450); // >= 4.5:1 trên nền trắng
  static const Color primaryLight = Color(0xFFE8F8EF);
  static const Color primaryTint = Color(0xFFF0FBF5);
  // High-contrast green for billing actions and small text on light surfaces.
  static const Color primaryStrong = Color(0xFF08744E);
  // Mobile grouping: distinct from the softer accents used inside content.
  static const Color mintSurface = Color(0xFFDEF2E7);
  static const Color mintBorder = Color(0xFFA7D4BC);
  static const Color sectionBorder = Color(0xFFD5DFDA);

  // Neutral colors
  static const Color background = Color(0xFFF7F8FA);
  static const Color card = Colors.white;
  static const Color textMain = Color(0xFF1F2933);
  static const Color textSub = Color(0xFF4B5563);
  static const Color textMuted = Color(0xFF6B7280); // >= 4.5:1 trên nền trắng
  static const Color border = Color(0xFFE5E7EB);

  // Semantic colors
  static const Color warning = Color(0xFFF59E0B);
  static const Color danger = Color(0xFFEF4444);
  static const Color success = Color(0xFF22C55E);
  static const Color premium = Color(0xFFF6C453);

  // Urgency card colors
  static const Color urgentBg = Color(0xFFFFF5F5);
  static const Color urgentBorder = Color(0x22EF4444);
  static const Color soonBg = Color(0xFFFFFBEB);
  static const Color soonBorder = Color(0x22F59E0B);
  static const Color normalBg = Color(0xFFE8F8EF);
  static const Color normalBorder = Color(0x222FBF71);

  // Radius tokens
  static const double radiusSm = 8.0;
  static const double radiusMd = 14.0;
  static const double radiusLg = 20.0;
  static const double radiusXl = 28.0;

  // Box shadows
  static List<BoxShadow> get softShadow => [
    BoxShadow(
      color: textMain.withValues(alpha: 0.05),
      blurRadius: 16,
      offset: const Offset(0, 4),
    ),
    BoxShadow(
      color: textMain.withValues(alpha: 0.02),
      blurRadius: 3,
      offset: const Offset(0, 1),
    ),
  ];

  static List<BoxShadow> get greenShadow => [
    BoxShadow(
      color: primary.withValues(alpha: 0.35),
      blurRadius: 16,
      offset: const Offset(0, 6),
    ),
  ];

  static ThemeData get themeData {
    return ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: background,
      colorScheme: ColorScheme.fromSeed(
        seedColor: primary,
        primary: primary,
        surface: background,
        brightness: Brightness.light,
      ),
      fontFamily: fontFamily,
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.white,
        foregroundColor: textMain,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontFamily: fontFamily,
          color: textMain,
          fontSize: 18,
          fontWeight: FontWeight.w700,
        ),
      ),
      cardTheme: CardThemeData(
        color: card,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusLg),
          side: const BorderSide(color: Color(0x0A000000)),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: const StadiumBorder(),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          textStyle: const TextStyle(
            fontFamily: fontFamily,
            fontWeight: FontWeight.w700,
            fontSize: 16,
          ),
        ),
      ),
      // Nút chữ (TextButton) cũng phải có font, nếu không máy Oppo sẽ dùng font viết tay.
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          textStyle: const TextStyle(
            fontFamily: fontFamily,
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: textSub,
          side: const BorderSide(color: border),
          shape: const StadiumBorder(),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          textStyle: const TextStyle(
            fontFamily: fontFamily,
            fontWeight: FontWeight.w600,
            fontSize: 15,
          ),
        ),
      ),
    );
  }

  // Helper for category emoji mapping matching Prototype
  static String getCategoryEmoji(String? category) =>
      groupOf(category: category, name: category ?? '').emoji;
}
