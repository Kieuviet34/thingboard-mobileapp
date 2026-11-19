import 'package:flutter/material.dart';
import 'package:thingsboard_democloud_app/config/themes/tb_theme.dart';

abstract class TbThemeUtils {
  static final MaterialColor tbPrimary = _mergeColors(Colors.teal, {
    500: Colors.teal[800]!,
  });
  static final MaterialColor tbAccent = Colors.deepOrange;
  static final Color tbPrimaryColor = tbPrimary[500]!;
  static final Color tbAccentColor = tbAccent[500]!;

  static ThemeData get defaultTheme =>
      tbTheme(tbPrimary, tbPrimaryColor, tbAccentColor);

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
