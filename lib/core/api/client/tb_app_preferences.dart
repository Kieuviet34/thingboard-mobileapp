import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:thingsboard_democloud_app/constants/app_constants.dart';
import 'package:thingsboard_democloud_app/core/models/auth_models.dart';

/// Non-secret host & UI preferences boundary (server URL, session mode, theme mode).
abstract interface class TbAppPreferences {
  Future<String> getServerBaseUrl();
  Future<void> setServerBaseUrl(String url);

  Future<SessionMode> getSessionMode();
  Future<void> setSessionMode(SessionMode mode);

  Future<ThemeMode> getThemeMode();
  Future<void> setThemeMode(ThemeMode mode);
}

abstract final class TbPrefKeys {
  static const serverBaseUrl = 'tb_server_base_url';
  static const sessionMode = 'tb_session_mode';
  static const themeMode = 'tb_theme_mode';
}

/// Production [TbAppPreferences] backed by `shared_preferences`.
final class SharedPreferencesImpl implements TbAppPreferences {
  SharedPreferencesImpl({SharedPreferencesAsync? prefs})
    : _prefs = prefs ?? SharedPreferencesAsync();

  final SharedPreferencesAsync _prefs;

  @override
  Future<String> getServerBaseUrl() async {
    final stored = await _prefs.getString(TbPrefKeys.serverBaseUrl);
    if (stored == null || stored.trim().isEmpty) {
      return ThingsboardAppConstants.thingsBoardApiEndpoint;
    }
    return stored;
  }

  @override
  Future<void> setServerBaseUrl(String url) =>
      _prefs.setString(TbPrefKeys.serverBaseUrl, url);

  @override
  Future<SessionMode> getSessionMode() async =>
      SessionMode.fromStorage(await _prefs.getString(TbPrefKeys.sessionMode));

  @override
  Future<void> setSessionMode(SessionMode mode) =>
      _prefs.setString(TbPrefKeys.sessionMode, mode.storageValue);

  @override
  Future<ThemeMode> getThemeMode() async {
    final value = await _prefs.getString(TbPrefKeys.themeMode);
    return switch (value) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
  }

  @override
  Future<void> setThemeMode(ThemeMode mode) =>
      _prefs.setString(TbPrefKeys.themeMode, mode.name);
}
