import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:thingsboard_democloud_app/config/themes/tb_theme_utils.dart';
import 'package:thingsboard_democloud_app/core/api/controllers/auth_controller.dart'
    as api_auth;
import 'package:thingsboard_democloud_app/core/auth/login/login_theme.dart';
import 'package:thingsboard_democloud_app/core/auth/login/widgets/o_auth_buttons.dart';

export 'package:thingsboard_democloud_app/core/api/controllers/auth_controller.dart'
    show AuthController, authRepositoryProvider;
export 'package:thingsboard_democloud_app/core/api/controllers/server_config_controller.dart'
    show
        dioClientProvider,
        serverConfigProvider,
        tbApiClientProvider,
        tbAppPreferencesProvider,
        tbStorageProvider,
        telemetryWsServiceProvider;

/// Canonical AsyncNotifier auth provider for Wave 2B+ screens and router guard.
final authSessionProvider = api_auth.authProvider;

/// Temporary UI-compatibility state preserved until Wave 2B migrates
/// `login_page.dart`, `main.dart`, and `home_placeholder_page.dart`.
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
  AuthNotifier(this._ref) : super(const AuthUiState());

  final Ref _ref;

  Future<void> login(String email, String password) async {
    await _ref.read(api_auth.authProvider.notifier).login(email, password);
    state = state.copyWith(isAuthenticated: true, userEmail: email);
  }

  Future<void> requestPasswordReset(String email) {
    return _ref
        .read(api_auth.authProvider.notifier)
        .requestPasswordReset(email);
  }

  Future<void> logout() async {
    await _ref.read(api_auth.authProvider.notifier).logout();
    state = state.copyWith(isAuthenticated: false, userEmail: '');
  }
}

/// Legacy bridge kept compiling for Wave 2B migration; new screens use [authSessionProvider]
/// or `auth_controller.dart`'s `authProvider`.
final authProvider = StateNotifierProvider<AuthNotifier, AuthUiState>((ref) {
  return AuthNotifier(ref);
});
