import 'package:flutter/material.dart';

/// Design tokens for spacing, shape radii, breakpoints, accessibility targets, and motion.
class DesignTokens {
  DesignTokens._();

  // Spacing tokens
  static const double spacing2 = 2.0;
  static const double spacing4 = 4.0;
  static const double spacing8 = 8.0;
  static const double spacing12 = 12.0;
  static const double spacing16 = 16.0;
  static const double spacing20 = 20.0;
  static const double spacing24 = 24.0;
  static const double spacing32 = 32.0;
  static const double spacing40 = 40.0;
  static const double spacing48 = 48.0;
  static const double spacing64 = 64.0;

  // Border radius tokens
  static const double radiusXs = 2.0;
  static const double radiusSmall = 4.0;
  static const double radiusMedium = 8.0;
  static const double radiusLarge = 12.0;
  static const double radiusXl = 16.0;
  static const double radiusRound = 100.0;

  // Elevation tokens
  static const double elevationNone = 0.0;
  static const double elevationSmall = 1.0;
  static const double elevationMedium = 2.0;
  static const double elevationLarge = 4.0;
  static const double elevationXl = 8.0;

  // Icon sizes
  static const double iconXs = 16.0;
  static const double iconSmall = 20.0;
  static const double iconMedium = 24.0;
  static const double iconLarge = 32.0;
  static const double iconXl = 40.0;

  // Accessibility & adaptive layout tokens
  static const double minTouchTarget = 48.0;
  static const double compactMaxWidth = 600.0;
  static const double mediumMaxWidth = 840.0;
  static const double maxReadableWidth = 720.0;

  // Motion durations
  static const Duration motionFast = Duration(milliseconds: 150);
  static const Duration motionMedium = Duration(milliseconds: 250);
  static const Duration motionSlow = Duration(milliseconds: 320);

  // Button heights
  static const double buttonHeightSmall = 32.0;
  static const double buttonHeightMedium = 40.0;
  static const double buttonHeightLarge = 48.0;

  // Input field heights
  static const double inputHeightSmall = 40.0;
  static const double inputHeightMedium = 48.0;
  static const double inputHeightLarge = 56.0;

  // Common edge insets
  static const EdgeInsets paddingXs = EdgeInsets.all(spacing4);
  static const EdgeInsets paddingSmall = EdgeInsets.all(spacing8);
  static const EdgeInsets paddingMedium = EdgeInsets.all(spacing16);
  static const EdgeInsets paddingLarge = EdgeInsets.all(spacing24);
  static const EdgeInsets paddingXl = EdgeInsets.all(spacing32);
  static const EdgeInsets paddingZero = EdgeInsets.zero;

  @Deprecated('Use paddingZero instead.')
  static const EdgeInsets paddigZero = EdgeInsets.zero;

  // Button padding
  static const EdgeInsets buttonPaddingSmall = EdgeInsets.symmetric(
    horizontal: spacing12,
    vertical: spacing8,
  );
  static const EdgeInsets buttonPaddingMedium = EdgeInsets.symmetric(
    horizontal: spacing16,
    vertical: spacing12,
  );
  static const EdgeInsets buttonPaddingLarge = EdgeInsets.symmetric(
    horizontal: spacing24,
    vertical: spacing16,
  );

  // Input padding
  static const EdgeInsets inputPadding = EdgeInsets.symmetric(
    horizontal: spacing16,
    vertical: spacing12,
  );

  // Card padding
  static const EdgeInsets cardPadding = EdgeInsets.all(spacing16);
  static const EdgeInsets cardPaddingLarge = EdgeInsets.all(spacing24);

  // Common border radius
  static BorderRadius get borderRadiusSmall =>
      BorderRadius.circular(radiusSmall);
  static BorderRadius get borderRadiusMedium =>
      BorderRadius.circular(radiusMedium);
  static BorderRadius get borderRadiusLarge =>
      BorderRadius.circular(radiusLarge);
  static BorderRadius get borderRadiusXl => BorderRadius.circular(radiusXl);
  static BorderRadius get borderRadiusRound =>
      BorderRadius.circular(radiusRound);
}
