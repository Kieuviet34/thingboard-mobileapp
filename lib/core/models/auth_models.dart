import 'package:flutter/material.dart';
import 'package:thingsboard_democloud_app/core/models/entity_id.dart';
import 'package:thingsboard_democloud_app/core/models/user_models.dart';

/// Runtime session mode across all repositories and controllers.
enum SessionMode {
  live('live'),
  demo('demo');

  const SessionMode(this.storageValue);

  final String storageValue;

  static SessionMode fromStorage(String? value) =>
      value == SessionMode.demo.storageValue
      ? SessionMode.demo
      : SessionMode.live;
}

/// JWT pair returned by `/api/auth/login`, `/api/auth/token`, 2FA, QR, and changePassword.
@immutable
class LoginResponse {
  const LoginResponse({required this.token, this.refreshToken, this.scope});

  factory LoginResponse.fromJson(Map<String, dynamic> json) {
    return LoginResponse(
      token: json['token'] as String? ?? '',
      refreshToken: json['refreshToken'] as String?,
      scope: json['scope'] != null
          ? Authority.fromWire(json['scope'] as String?)
          : null,
    );
  }

  final String token;
  final String? refreshToken;
  final Authority? scope;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'token': token,
    if (refreshToken != null) 'refreshToken': refreshToken,
    if (scope != null) 'scope': scope!.wireValue,
  };
}

/// Available 2FA provider returned by `GET /api/auth/2fa/providers`.
@immutable
class TwoFaProviderInfo {
  const TwoFaProviderInfo({
    required this.type,
    this.isDefault = false,
    this.contact,
  });

  factory TwoFaProviderInfo.fromJson(Map<String, dynamic> json) {
    return TwoFaProviderInfo(
      type: json['type'] as String? ?? 'TOTP',
      isDefault: json['default'] as bool? ?? false,
      contact: json['contact'] as String?,
    );
  }

  final String type;
  final bool isDefault;
  final String? contact;
}

/// OAuth2 login button metadata returned by `POST /api/noauth/oauth2Clients`.
@immutable
class OAuth2ClientModel {
  const OAuth2ClientModel({required this.name, required this.icon, this.url});

  factory OAuth2ClientModel.fromJson(Map<String, dynamic> json) {
    return OAuth2ClientModel(
      name: json['name'] as String? ?? '',
      icon: json['icon'] as String? ?? '',
      url: json['url'] as String?,
    );
  }

  final String name;
  final String icon;
  final String? url;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is OAuth2ClientModel &&
          runtimeType == other.runtimeType &&
          name == other.name &&
          icon == other.icon &&
          url == other.url;

  @override
  int get hashCode => Object.hash(name, icon, url);
}

/// Password complexity rules returned by `GET /api/noauth/userPasswordPolicy`.
@immutable
class UserPasswordPolicy {
  const UserPasswordPolicy({
    this.minimumLength = 6,
    this.minimumUppercaseLetters,
    this.minimumLowercaseLetters,
    this.minimumDigits,
    this.minimumSpecialCharacters,
    this.allowWhitespaces = true,
  });

  factory UserPasswordPolicy.fromJson(Map<String, dynamic> json) {
    return UserPasswordPolicy(
      minimumLength: (json['minimumLength'] as num?)?.toInt() ?? 6,
      minimumUppercaseLetters: (json['minimumUppercaseLetters'] as num?)
          ?.toInt(),
      minimumLowercaseLetters: (json['minimumLowercaseLetters'] as num?)
          ?.toInt(),
      minimumDigits: (json['minimumDigits'] as num?)?.toInt(),
      minimumSpecialCharacters: (json['minimumSpecialCharacters'] as num?)
          ?.toInt(),
      allowWhitespaces: json['allowWhitespaces'] as bool? ?? true,
    );
  }

  final int minimumLength;
  final int? minimumUppercaseLetters;
  final int? minimumLowercaseLetters;
  final int? minimumDigits;
  final int? minimumSpecialCharacters;
  final bool allowWhitespaces;
}

/// Optional mobile startup info returned by `GET /api/noauth/mobile` (PE 4.4+).
@immutable
class LoginMobileInfo {
  const LoginMobileInfo({
    this.oAuth2Clients = const [],
    this.selfRegistrationEnabled = false,
  });

  factory LoginMobileInfo.fromJson(Map<String, dynamic> json) {
    final rawClients =
        json['oAuth2ClientLoginInfos'] as List<dynamic>? ?? const [];
    return LoginMobileInfo(
      oAuth2Clients: rawClients
          .whereType<Map<String, dynamic>>()
          .map(OAuth2ClientModel.fromJson)
          .toList(growable: false),
      selfRegistrationEnabled: json['selfRegistrationParams'] != null,
    );
  }

  final List<OAuth2ClientModel> oAuth2Clients;
  final bool selfRegistrationEnabled;
}

/// Authenticated user session credentials & claims decoded from JWT.
@immutable
class TbAuthSession {
  const TbAuthSession({
    required this.accessToken,
    required this.refreshToken,
    required this.userId,
    required this.email,
    required this.authority,
    this.tenantId,
    this.customerId,
    this.expiresAt,
  });

  final String accessToken;
  final String refreshToken;
  final String userId;
  final String email;
  final Authority authority;
  final String? tenantId;
  final String? customerId;
  final DateTime? expiresAt;
}

/// Sealed authentication state driving `GoRouter` redirect and app session lifecycle.
sealed class AuthState {
  const AuthState();

  bool get isAuthenticated => this is AuthAuthenticated;
  bool get isDemo =>
      this is AuthAuthenticated &&
      (this as AuthAuthenticated).mode == SessionMode.demo;
}

@immutable
final class AuthUnauthenticated extends AuthState {
  const AuthUnauthenticated();

  @override
  bool operator ==(Object other) => other is AuthUnauthenticated;

  @override
  int get hashCode => runtimeType.hashCode;
}

@immutable
final class AuthMfaVerificationRequired extends AuthState {
  const AuthMfaVerificationRequired({
    required this.preAuthToken,
    required this.providers,
  });

  final String preAuthToken;
  final List<TwoFaProviderInfo> providers;
}

@immutable
final class AuthMfaConfigurationRequired extends AuthState {
  const AuthMfaConfigurationRequired({required this.preAuthToken});

  final String preAuthToken;
}

@immutable
final class AuthAuthenticated extends AuthState {
  const AuthAuthenticated({
    required this.session,
    required this.user,
    required this.mode,
  });

  final TbAuthSession session;
  final TbUserProfile user;
  final SessionMode mode;
}

/// Non-secret host & capability configuration managed by `ServerConfigController`.
@immutable
class ServerConfigState {
  const ServerConfigState({
    required this.baseUrl,
    this.mode = SessionMode.live,
    this.themeMode = ThemeMode.system,
    this.passwordPolicy,
    this.oauthClients = const [],
    this.mobileInfo,
    this.serverVersion,
    this.sessionGeneration = 0,
  });

  final String baseUrl;
  final SessionMode mode;
  final ThemeMode themeMode;
  final UserPasswordPolicy? passwordPolicy;
  final List<OAuth2ClientModel> oauthClients;
  final LoginMobileInfo? mobileInfo;
  final String? serverVersion;
  final int sessionGeneration;

  ServerConfigState copyWith({
    String? baseUrl,
    SessionMode? mode,
    ThemeMode? themeMode,
    UserPasswordPolicy? passwordPolicy,
    List<OAuth2ClientModel>? oauthClients,
    LoginMobileInfo? mobileInfo,
    bool clearMobileInfo = false,
    String? serverVersion,
    bool clearServerVersion = false,
    int? sessionGeneration,
  }) {
    return ServerConfigState(
      baseUrl: baseUrl ?? this.baseUrl,
      mode: mode ?? this.mode,
      themeMode: themeMode ?? this.themeMode,
      passwordPolicy: passwordPolicy ?? this.passwordPolicy,
      oauthClients: oauthClients ?? this.oauthClients,
      mobileInfo: clearMobileInfo ? null : (mobileInfo ?? this.mobileInfo),
      serverVersion: clearServerVersion
          ? null
          : (serverVersion ?? this.serverVersion),
      sessionGeneration: sessionGeneration ?? this.sessionGeneration,
    );
  }
}
