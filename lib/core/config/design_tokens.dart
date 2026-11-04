import 'package:flutter/material.dart';

/// Design tokens chuẩn cho toàn bộ ứng dụng HomeMind.
/// Bao gồm khoảng cách (spacing), bán kính góc bo (border radius), và độ mờ.
abstract class DesignTokens {
  // Spacing & Padding
  static const double space2 = 2.0;
  static const double space4 = 4.0;
  static const double space8 = 8.0;
  static const double space12 = 12.0;
  static const double space16 = 16.0;
  static const double space20 = 20.0;
  static const double space24 = 24.0;
  static const double space32 = 32.0;
  static const double space40 = 40.0;
  static const double space48 = 48.0;

  // Border Radius
  static const double radiusSmall = 6.0;
  static const double radiusMedium = 12.0;
  static const double radiusLarge = 16.0;
  static const double radiusXLarge = 24.0;
  static const double radiusCircular = 999.0;

  // Elevation / Shadow
  static const double elevationLow = 1.0;
  static const double elevationMedium = 3.0;
  static const double elevationHigh = 6.0;

  // Durations for smooth micro-animations
  static const Duration durationFast = Duration(milliseconds: 150);
  static const Duration durationMedium = Duration(milliseconds: 300);
  static const Duration durationSlow = Duration(milliseconds: 500);

  // Border Radius Objects
  static const BorderRadius borderSmall = BorderRadius.all(Radius.circular(radiusSmall));
  static const BorderRadius borderMedium = BorderRadius.all(Radius.circular(radiusMedium));
  static const BorderRadius borderLarge = BorderRadius.all(Radius.circular(radiusLarge));
  static const BorderRadius borderXLarge = BorderRadius.all(Radius.circular(radiusXLarge));

  // Opacity Tokens
  static const double opacitySubtle = 0.04;
  static const double opacityMuted = 0.38;
  static const double opacityMedium = 0.60;
  static const double opacityHigh = 0.87;
}
