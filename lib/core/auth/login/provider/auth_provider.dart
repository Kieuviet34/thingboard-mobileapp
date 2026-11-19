import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:thingsboard_democloud_app/config/themes/tb_theme_utils.dart';
import 'package:thingsboard_democloud_app/constants/app_constants.dart';
import 'package:thingsboard_democloud_app/core/auth/login/login_theme.dart';
import 'package:thingsboard_democloud_app/core/auth/login/widgets/o_auth_buttons.dart';

/// Pre-configured Dio HTTP client pointing to https://thingsboard.democloud.xyz/
/// Ready for backend integration in the next phase.
final dioClientProvider = Provider<Dio>((ref) {
  return Dio(
    BaseOptions(
      baseUrl: ThingsboardAppConstants.thingsBoardApiEndpoint,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 15),
      headers: {'Content-Type': 'application/json'},
    ),
  );
});

class AuthUiState {
  const AuthUiState({
    this.isAuthenticated = false,
    this.userEmail = '',
    this.darkForeground = false,
    this.selfRegistrationEnabled = false,
    this.oauthClients = const [
      OAuth2ClientInfo(name: 'qr', icon: 'qr-code-logo'),
    ],
  });

  final bool isAuthenticated;
  final String userEmail;
  final bool darkForeground;
  final bool selfRegistrationEnabled;
  final List<OAuth2ClientInfo> oauthClients;

  ThemeData get appTheme => TbThemeUtils.defaultTheme;
  ThemeData get loginTheme =>
      loginPageTheme(TbThemeUtils.defaultTheme, darkForeground: darkForeground);

  AuthUiState copyWith({
    bool? isAuthenticated,
    String? userEmail,
    bool? darkForeground,
    bool? selfRegistrationEnabled,
    List<OAuth2ClientInfo>? oauthClients,
  }) {
    return AuthUiState(
      isAuthenticated: isAuthenticated ?? this.isAuthenticated,
      userEmail: userEmail ?? this.userEmail,
      darkForeground: darkForeground ?? this.darkForeground,
      selfRegistrationEnabled:
          selfRegistrationEnabled ?? this.selfRegistrationEnabled,
      oauthClients: oauthClients ?? this.oauthClients,
    );
  }
}

class AuthNotifier extends StateNotifier<AuthUiState> {
  AuthNotifier() : super(const AuthUiState());

  /// UI replica login handler (simulates network latency, ready to wire to
  /// POST https://thingsboard.democloud.xyz/api/auth/login later).
  Future<void> login(String email, String password) async {
    await Future<void>.delayed(const Duration(milliseconds: 800));
    state = state.copyWith(isAuthenticated: true, userEmail: email);
  }

  /// UI replica password reset handler (simulates network latency, ready to wire to
  /// POST https://thingsboard.democloud.xyz/api/noauth/resetPasswordByEmail later).
  Future<void> requestPasswordReset(String email) async {
    await Future<void>.delayed(const Duration(milliseconds: 800));
  }

  Future<void> logout() async {
    state = state.copyWith(isAuthenticated: false, userEmail: '');
  }
}

final authProvider = StateNotifierProvider<AuthNotifier, AuthUiState>((ref) {
  return AuthNotifier();
});
