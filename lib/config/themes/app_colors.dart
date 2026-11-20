import 'package:flutter/material.dart';

/// Brand and semantic color tokens for ThingsBoard PE Light & Dark M3 themes.
class AppColors {
  AppColors._();

  // Primary Brand Colors (ThingsBoard PE Blue + High-Contrast Accent)
  static const primaryBlue = Color(0xFF305680);
  static const secondaryBlue = Color(0xFF527DAD);
  static const accentOrange = Color(0xFFE65100);
  static const darkPrimaryBlue = Color(0xFFA4C8FF);

  // Surface Colors
  static const white = Color(0xFFFFFFFF);
  static const scaffoldBackground = Color(0xFFF8FAFC);
  static const surfaceLight = Color(0xFFF1F5F9);
  static const surfaceDark = Color(0xFF0F141A);
  static const black = Color(0xFF000000);

  // Legacy / Compatibility Text Colors (prefer Theme.of(context).colorScheme in new code)
  static const textPrimary = Color(0xDE000000);
  static const textSecondary = Color(0xC2000000);
  static const textTertiary = Color(0x8A000000);
  static const textDisabled = Color(0x61000000);
  static const textWhite = Color(0xFFFFFFFF);
  static const textDark = Color(0xFF282828);

  // Legacy / Compatibility Icon Colors
  static const iconSecondary = Color(0xC2000000);
  static const iconTertiary = Color(0x8A000000);
  static const iconDisabled = Color(0x61000000);

  // Border Colors
  static const bordersLight = Color(0x1F000000);
  static const borderError = Color(0xFFBA1A1A);

  // State Colors
  static const textError = Color(0xFFBA1A1A);
  static const notificationInfo = Color(0xFF305680);
  static const notificationWarning = Color(0xFFC43E00);
  static const notificationSuccess = Color(0xFF0F6D31);
  static const notificationError = Color(0xFFBA1A1A);

  // Overlay Colors
  static const bgOverlay = Color(0x61000000);
  static const cameraBackground = Color(0xFF14181F);

  // Selection and Focus Colors
  static const selectionColor = Color(0x33305680);
  static const focusColor = primaryBlue;

  // Material Color Swatch for Primary Blue
  static const MaterialColor primarySwatch =
      MaterialColor(0xFF305680, <int, Color>{
        50: Color(0xFFE8EEF5),
        100: Color(0xFFC6D5E6),
        200: Color(0xFFA0B9D6),
        300: Color(0xFF7A9DC6),
        400: Color(0xFF5D88B9),
        500: primaryBlue,
        600: secondaryBlue,
        700: Color(0xFF27476B),
        800: Color(0xFF1E3856),
        900: Color(0xFF122338),
      });

  // Dark Theme Material Color Swatch
  static const MaterialColor darkPrimarySwatch =
      MaterialColor(0xFFA4C8FF, <int, Color>{
        50: Color(0xFFE8F1FF),
        100: Color(0xFFC7DDFF),
        200: darkPrimaryBlue,
        300: Color(0xFF7BB0FF),
        400: Color(0xFF5C9BFF),
        500: darkPrimaryBlue,
        600: secondaryBlue,
        700: Color(0xFF27476B),
        800: primaryBlue,
        900: Color(0xFF122338),
      });

  static Color get appPrimaryColor => primaryBlue;
}
