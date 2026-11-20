import 'package:flutter/material.dart';
import 'package:thingsboard_democloud_app/config/themes/tb_theme.dart';

/// Returns a Material 3 theme for the login screen respecting [darkForeground]
/// or the active brightness.
ThemeData loginPageTheme(ThemeData base, {required bool darkForeground}) {
  if (base.brightness == Brightness.dark) {
    return tbDarkTheme();
  }
  return darkForeground ? tbLightTheme() : base;
}
