import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:thingsboard_democloud_app/config/themes/app_colors.dart';
import 'package:thingsboard_democloud_app/config/themes/tb_theme.dart';

/// App-wide Light/Dark/System [ThemeMode] controller.
class TbThemeModeNotifier extends Notifier<ThemeMode> {
  @override
  ThemeMode build() => ThemeMode.system;

  void setThemeMode(ThemeMode mode) {
    if (state != mode) {
      state = mode;
    }
  }
}

final themeModeProvider = NotifierProvider<TbThemeModeNotifier, ThemeMode>(
  TbThemeModeNotifier.new,
);

abstract class TbThemeUtils {
  static final MaterialColor tbPrimary = AppColors.primarySwatch;
  static final MaterialColor tbAccent = _mergeColors(Colors.deepOrange, {
    500: AppColors.accentOrange,
  });
  static final Color tbPrimaryColor = AppColors.primaryBlue;
  static final Color tbAccentColor = AppColors.accentOrange;

  static ThemeData get lightTheme => tbLightTheme();
  static ThemeData get darkTheme => tbDarkTheme();
  static ThemeData get defaultTheme => tbLightTheme();

  static MaterialColor _mergeColors(
    MaterialColor color,
    Map<int, Color> overrides,
  ) {
    final swatch = <int, Color>{
      50: overrides[50] ?? color[50]!,
      100: overrides[100] ?? color[100]!,
      200: overrides[200] ?? color[200]!,
      300: overrides[300] ?? color[300]!,
      400: overrides[400] ?? color[400]!,
      500: overrides[500] ?? color[500]!,
      600: overrides[600] ?? color[600]!,
      700: overrides[700] ?? color[700]!,
      800: overrides[800] ?? color[800]!,
      900: overrides[900] ?? color[900]!,
    };
    return MaterialColor(swatch[500]!.toARGB32(), swatch);
  }
}
