import 'package:flutter/material.dart';

/// Typography scale and tabular numeric helpers for ThingsBoard PE M3 UI.
abstract final class TbTextStyles {
  static const titleLarge = TextStyle(
    fontWeight: FontWeight.w500,
    fontSize: 28,
    height: 1.28,
    letterSpacing: 0.25,
  );

  static const titleMedium = TextStyle(
    fontWeight: FontWeight.w500,
    fontSize: 24,
    height: 1.33,
    letterSpacing: 0,
  );

  static const titleSmall = TextStyle(
    fontWeight: FontWeight.w500,
    fontSize: 20,
    height: 1.2,
    letterSpacing: 0.01,
  );

  static const titleXs = TextStyle(
    fontWeight: FontWeight.w500,
    fontSize: 18,
    height: 1.33,
    letterSpacing: 0.15,
  );

  static const bodyLarge = TextStyle(
    fontWeight: FontWeight.w400,
    fontSize: 16,
    height: 1.5,
    letterSpacing: 0.15,
  );

  static const bodyMedium = TextStyle(
    fontWeight: FontWeight.w400,
    fontSize: 14,
    height: 1.43,
    letterSpacing: 0.2,
  );

  static const bodySmall = TextStyle(
    fontWeight: FontWeight.w400,
    fontSize: 12,
    height: 1.33,
    letterSpacing: 0.4,
  );

  static const bodyRegular = TextStyle(
    fontWeight: FontWeight.w400,
    fontSize: 17,
    height: 1.5,
    letterSpacing: -0.41,
  );

  static const labelLarge = TextStyle(
    fontWeight: FontWeight.w500,
    fontSize: 16,
    height: 1.5,
    letterSpacing: 0.25,
  );

  static const labelMedium = TextStyle(
    fontWeight: FontWeight.w500,
    fontSize: 14,
    height: 1.43,
    letterSpacing: 0.25,
  );

  static const labelSmall = TextStyle(
    fontWeight: FontWeight.w400,
    fontSize: 12,
    height: 1.33,
    letterSpacing: 0.4,
  );

  static const titleSmallSb = TextStyle(
    fontWeight: FontWeight.w600,
    fontSize: 20,
    height: 1.2,
    letterSpacing: 0.01,
  );

  static const caption = TextStyle(
    fontWeight: FontWeight.w400,
    fontSize: 11,
    height: 1.45,
    letterSpacing: 0.25,
  );

  static const button = TextStyle(
    fontWeight: FontWeight.w500,
    fontSize: 14,
    height: 1.43,
    letterSpacing: 0.25,
  );

  /// Applies `tabularFigures` so live telemetry metrics do not shift horizontally.
  static TextStyle tabular(TextStyle style) =>
      style.copyWith(fontFeatures: const [FontFeature.tabularFigures()]);

  static const metricValue = TextStyle(
    fontWeight: FontWeight.w600,
    fontSize: 14,
    height: 1.3,
    fontFeatures: [FontFeature.tabularFigures()],
  );

  static const metricLabel = TextStyle(
    fontWeight: FontWeight.w500,
    fontSize: 11,
    height: 1.25,
    letterSpacing: 0.3,
  );
}
