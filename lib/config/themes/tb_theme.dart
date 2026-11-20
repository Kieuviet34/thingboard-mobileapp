import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:thingsboard_democloud_app/config/themes/app_colors.dart';
import 'package:thingsboard_democloud_app/config/themes/design_tokens.dart';
import 'package:thingsboard_democloud_app/config/themes/tb_status_colors.dart';
import 'package:thingsboard_democloud_app/config/themes/tb_text_styles.dart';
import 'package:thingsboard_democloud_app/utils/transition/page_transitions.dart';

final Typography tbTypography = Typography.material2021();

/// Builds the canonical Material 3 Light theme for ThingsBoard PE.
ThemeData tbLightTheme() => _buildM3Theme(
  brightness: Brightness.light,
  primaryColor: AppColors.primaryBlue,
  secondaryColor: AppColors.secondaryBlue,
  tertiaryColor: AppColors.accentOrange,
);

/// Builds the canonical Material 3 Dark theme for ThingsBoard PE.
ThemeData tbDarkTheme() => _buildM3Theme(
  brightness: Brightness.dark,
  primaryColor: AppColors.primaryBlue,
  secondaryColor: AppColors.secondaryBlue,
  tertiaryColor: AppColors.accentOrange,
);

/// Backward-compatible theme factory upgraded to Material 3 (`useMaterial3: true`).
ThemeData tbTheme(
  MaterialColor primarySwatch,
  Color primaryColor,
  Color accentColor, {
  Brightness brightness = Brightness.light,
}) {
  return _buildM3Theme(
    brightness: brightness,
    primaryColor: primaryColor,
    secondaryColor: accentColor,
    tertiaryColor: AppColors.accentOrange,
  );
}

ThemeData _buildM3Theme({
  required Brightness brightness,
  required Color primaryColor,
  required Color secondaryColor,
  required Color tertiaryColor,
}) {
  final isDark = brightness == Brightness.dark;
  final baseScheme = ColorScheme.fromSeed(
    seedColor: primaryColor,
    brightness: brightness,
  );
  final scheme = baseScheme.copyWith(
    primary: isDark ? baseScheme.primary : primaryColor,
    secondary: isDark ? baseScheme.secondary : secondaryColor,
    tertiary: isDark ? baseScheme.tertiary : tertiaryColor,
  );
  final statusColors = isDark ? TbStatusColors.dark() : TbStatusColors.light();
  final baseTextTheme = (isDark ? tbTypography.white : tbTypography.black)
      .apply(bodyColor: scheme.onSurface, displayColor: scheme.onSurface);

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    primaryColor: scheme.primary,
    colorScheme: scheme,
    typography: tbTypography,
    textTheme: baseTextTheme,
    primaryTextTheme: baseTextTheme,
    scaffoldBackgroundColor: scheme.surface,
    extensions: <ThemeExtension<dynamic>>[statusColors],
    appBarTheme: _appBarTheme(scheme, baseTextTheme, isDark),
    navigationBarTheme: _navigationBarTheme(scheme, baseTextTheme),
    navigationRailTheme: _navigationRailTheme(scheme, baseTextTheme),
    bottomNavigationBarTheme: _bottomNavTheme(scheme),
    cardTheme: _cardTheme(scheme),
    chipTheme: _chipTheme(scheme, baseTextTheme),
    dividerTheme: _dividerTheme(scheme),
    listTileTheme: _listTileTheme(scheme),
    iconTheme: IconThemeData(
      color: scheme.onSurfaceVariant,
      size: DesignTokens.iconMedium,
    ),
    inputDecorationTheme: _inputTheme(scheme, baseTextTheme),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: scheme.primary,
      selectionHandleColor: scheme.primary,
      selectionColor: scheme.primary.withValues(alpha: 0.25),
    ),
    filledButtonTheme: _filledButtonTheme(scheme),
    elevatedButtonTheme: _elevatedButtonTheme(scheme),
    outlinedButtonTheme: _outlinedButtonTheme(scheme),
    textButtonTheme: _textButtonTheme(scheme),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: scheme.inverseSurface,
      contentTextStyle: baseTextTheme.bodyMedium?.copyWith(
        color: scheme.onInverseSurface,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: DesignTokens.borderRadiusLarge,
      ),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: scheme.primary,
      linearTrackColor: scheme.surfaceContainerHighest,
    ),
    indicatorColor: scheme.primary,
    pageTransitionsTheme: pageTransitionsTheme,
  );
}

const PageTransitionsTheme pageTransitionsTheme = PageTransitionsTheme(
  builders: {
    TargetPlatform.iOS: FadeOpenPageTransitionsBuilder(),
    TargetPlatform.android: FadeOpenPageTransitionsBuilder(),
  },
);

AppBarTheme _appBarTheme(ColorScheme scheme, TextTheme textTheme, bool isDark) {
  return AppBarTheme(
    systemOverlayStyle: isDark
        ? SystemUiOverlayStyle.light
        : SystemUiOverlayStyle.dark,
    backgroundColor: scheme.surface,
    foregroundColor: scheme.onSurface,
    surfaceTintColor: Colors.transparent,
    scrolledUnderElevation: 2,
    elevation: 0,
    centerTitle: false,
    iconTheme: IconThemeData(
      color: scheme.onSurfaceVariant,
      size: DesignTokens.iconMedium,
    ),
    titleTextStyle: textTheme.titleLarge?.copyWith(
      color: scheme.onSurface,
      fontWeight: FontWeight.w600,
    ),
  );
}

NavigationBarThemeData _navigationBarTheme(
  ColorScheme scheme,
  TextTheme textTheme,
) {
  return NavigationBarThemeData(
    backgroundColor: scheme.surfaceContainer,
    surfaceTintColor: Colors.transparent,
    indicatorColor: scheme.secondaryContainer,
    labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
    iconTheme: WidgetStateProperty.resolveWith((states) {
      final selected = states.contains(WidgetState.selected);
      return IconThemeData(
        color: selected ? scheme.onSecondaryContainer : scheme.onSurfaceVariant,
        size: DesignTokens.iconMedium,
      );
    }),
    labelTextStyle: WidgetStateProperty.resolveWith((states) {
      final selected = states.contains(WidgetState.selected);
      return textTheme.labelMedium?.copyWith(
        fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
        color: selected ? scheme.onSurface : scheme.onSurfaceVariant,
      );
    }),
  );
}

NavigationRailThemeData _navigationRailTheme(
  ColorScheme scheme,
  TextTheme textTheme,
) {
  return NavigationRailThemeData(
    backgroundColor: scheme.surfaceContainerLow,
    indicatorColor: scheme.secondaryContainer,
    selectedIconTheme: IconThemeData(color: scheme.onSecondaryContainer),
    unselectedIconTheme: IconThemeData(color: scheme.onSurfaceVariant),
    selectedLabelTextStyle: textTheme.labelMedium?.copyWith(
      fontWeight: FontWeight.w600,
      color: scheme.onSurface,
    ),
    unselectedLabelTextStyle: textTheme.labelMedium?.copyWith(
      color: scheme.onSurfaceVariant,
    ),
  );
}

BottomNavigationBarThemeData _bottomNavTheme(ColorScheme scheme) {
  return BottomNavigationBarThemeData(
    backgroundColor: scheme.surfaceContainer,
    selectedItemColor: scheme.primary,
    unselectedItemColor: scheme.onSurfaceVariant,
    showSelectedLabels: true,
    showUnselectedLabels: true,
    type: BottomNavigationBarType.fixed,
  );
}

CardThemeData _cardTheme(ColorScheme scheme) {
  return CardThemeData(
    color: scheme.surfaceContainerLow,
    surfaceTintColor: Colors.transparent,
    elevation: DesignTokens.elevationNone,
    shape: RoundedRectangleBorder(
      borderRadius: DesignTokens.borderRadiusLarge,
      side: BorderSide(color: scheme.outlineVariant),
    ),
    margin: DesignTokens.paddingZero,
  );
}

ChipThemeData _chipTheme(ColorScheme scheme, TextTheme textTheme) {
  return ChipThemeData(
    backgroundColor: scheme.surfaceContainerLow,
    selectedColor: scheme.secondaryContainer,
    side: BorderSide(color: scheme.outlineVariant),
    shape: RoundedRectangleBorder(
      borderRadius: DesignTokens.borderRadiusMedium,
    ),
    labelStyle: textTheme.labelMedium?.copyWith(color: scheme.onSurface),
  );
}

DividerThemeData _dividerTheme(ColorScheme scheme) {
  return DividerThemeData(color: scheme.outlineVariant, thickness: 1, space: 1);
}

ListTileThemeData _listTileTheme(ColorScheme scheme) {
  return ListTileThemeData(
    contentPadding: const EdgeInsets.symmetric(
      horizontal: DesignTokens.spacing16,
      vertical: DesignTokens.spacing4,
    ),
    minVerticalPadding: DesignTokens.spacing8,
    minTileHeight: DesignTokens.minTouchTarget,
    iconColor: scheme.onSurfaceVariant,
    textColor: scheme.onSurface,
    shape: RoundedRectangleBorder(borderRadius: DesignTokens.borderRadiusLarge),
  );
}

FilledButtonThemeData _filledButtonTheme(ColorScheme scheme) {
  return FilledButtonThemeData(
    style: FilledButton.styleFrom(
      padding: DesignTokens.buttonPaddingMedium,
      textStyle: TbTextStyles.button,
      shape: RoundedRectangleBorder(
        borderRadius: DesignTokens.borderRadiusLarge,
      ),
      minimumSize: const Size(
        DesignTokens.minTouchTarget,
        DesignTokens.buttonHeightLarge,
      ),
    ),
  );
}

ElevatedButtonThemeData _elevatedButtonTheme(ColorScheme scheme) {
  return ElevatedButtonThemeData(
    style: ElevatedButton.styleFrom(
      backgroundColor: scheme.primary,
      foregroundColor: scheme.onPrimary,
      padding: DesignTokens.buttonPaddingMedium,
      textStyle: TbTextStyles.button,
      elevation: DesignTokens.elevationSmall,
      shape: RoundedRectangleBorder(
        borderRadius: DesignTokens.borderRadiusLarge,
      ),
      minimumSize: const Size(
        DesignTokens.minTouchTarget,
        DesignTokens.buttonHeightLarge,
      ),
    ),
  );
}

OutlinedButtonThemeData _outlinedButtonTheme(ColorScheme scheme) {
  return OutlinedButtonThemeData(
    style: OutlinedButton.styleFrom(
      foregroundColor: scheme.primary,
      side: BorderSide(color: scheme.outline),
      padding: DesignTokens.buttonPaddingMedium,
      textStyle: TbTextStyles.button,
      shape: RoundedRectangleBorder(
        borderRadius: DesignTokens.borderRadiusLarge,
      ),
      minimumSize: const Size(
        DesignTokens.minTouchTarget,
        DesignTokens.buttonHeightLarge,
      ),
    ),
  );
}

TextButtonThemeData _textButtonTheme(ColorScheme scheme) {
  return TextButtonThemeData(
    style: TextButton.styleFrom(
      foregroundColor: scheme.primary,
      padding: DesignTokens.buttonPaddingMedium,
      textStyle: TbTextStyles.button,
      shape: RoundedRectangleBorder(
        borderRadius: DesignTokens.borderRadiusLarge,
      ),
      minimumSize: const Size(
        DesignTokens.minTouchTarget,
        DesignTokens.buttonHeightMedium,
      ),
    ),
  );
}

InputDecorationTheme _inputTheme(ColorScheme scheme, TextTheme textTheme) {
  final radius = DesignTokens.borderRadiusLarge;
  return InputDecorationTheme(
    filled: true,
    fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.45),
    isDense: true,
    contentPadding: DesignTokens.inputPadding,
    labelStyle: textTheme.bodyLarge?.copyWith(color: scheme.onSurfaceVariant),
    helperStyle: textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
    floatingLabelStyle: WidgetStateTextStyle.resolveWith((states) {
      final color = states.contains(WidgetState.error)
          ? scheme.error
          : states.contains(WidgetState.focused)
          ? scheme.primary
          : scheme.onSurfaceVariant;
      return textTheme.labelMedium?.copyWith(color: color) ??
          TbTextStyles.labelSmall.copyWith(color: color);
    }),
    hintStyle: textTheme.bodyLarge?.copyWith(
      color: scheme.onSurfaceVariant.withValues(alpha: 0.75),
    ),
    errorStyle: textTheme.bodySmall?.copyWith(color: scheme.error),
    focusedBorder: OutlineInputBorder(
      borderSide: BorderSide(color: scheme.primary, width: 2),
      borderRadius: radius,
    ),
    enabledBorder: OutlineInputBorder(
      borderSide: BorderSide(color: scheme.outlineVariant),
      borderRadius: radius,
    ),
    border: OutlineInputBorder(
      borderSide: BorderSide(color: scheme.outlineVariant),
      borderRadius: radius,
    ),
    focusedErrorBorder: OutlineInputBorder(
      borderSide: BorderSide(color: scheme.error, width: 2),
      borderRadius: radius,
    ),
    errorBorder: OutlineInputBorder(
      borderSide: BorderSide(color: scheme.error),
      borderRadius: radius,
    ),
    focusColor: scheme.primary,
  );
}
