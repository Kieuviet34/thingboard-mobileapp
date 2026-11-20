import 'package:flutter/material.dart';
import 'package:thingsboard_democloud_app/constants/app_constants.dart';
import 'package:thingsboard_democloud_app/core/api/client/tb_app_preferences.dart';
import 'package:thingsboard_democloud_app/core/models/auth_models.dart';

/// In-memory [TbAppPreferences] fake for unit and widget tests.
class FakeAppPreferences implements TbAppPreferences {
  FakeAppPreferences({
    this.serverBaseUrl = ThingsboardAppConstants.defaultApiEndpoint,
    this.sessionMode = SessionMode.live,
    this.themeMode = ThemeMode.system,
  });

  String serverBaseUrl;
  SessionMode sessionMode;
  ThemeMode themeMode;

  @override
  Future<String> getServerBaseUrl() async => serverBaseUrl;

  @override
  Future<void> setServerBaseUrl(String url) async {
    serverBaseUrl = url;
  }

  @override
  Future<SessionMode> getSessionMode() async => sessionMode;

  @override
  Future<void> setSessionMode(SessionMode mode) async {
    sessionMode = mode;
  }

  @override
  Future<ThemeMode> getThemeMode() async => themeMode;

  @override
  Future<void> setThemeMode(ThemeMode mode) async {
    themeMode = mode;
  }
}
