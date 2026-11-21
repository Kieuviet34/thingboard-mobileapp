import 'package:dio/dio.dart';
import 'package:thingsboard_democloud_app/core/api/client/tb_api_client.dart';
import 'package:thingsboard_democloud_app/core/models/auth_models.dart';
import 'package:thingsboard_democloud_app/core/models/entity_id.dart';
import 'package:thingsboard_democloud_app/core/models/user_models.dart';

/// Authentication, 2FA, QR-login, and password-reset REST boundary.
abstract interface class AuthRepository {
  Future<LoginResponse> login(String username, String password);
  Future<TbUserProfile> getCurrentUser();
  Future<void> logout();
  Future<void> requestPasswordReset(String email);
  Future<List<TwoFaProviderInfo>> getTwoFaProviders(String preAuthToken);
  Future<void> sendTwoFaVerificationCode({
    required String preAuthToken,
    required String providerType,
  });
  Future<LoginResponse> checkTwoFaVerificationCode({
    required String preAuthToken,
    required String providerType,
    required String verificationCode,
  });
  Future<LoginResponse> authenticateByMfaConfigurationToken(
    String preAuthToken,
  );
  Future<LoginResponse> loginByQrSecret(String secret);
}

final class RestAuthRepository implements AuthRepository {
  RestAuthRepository({required TbApiClient client}) : _client = client;

  final TbApiClient _client;

  @override
  Future<LoginResponse> login(String username, String password) async {
    final response = await _client.post<Map<String, dynamic>>(
      '/api/auth/login',
      data: <String, dynamic>{'username': username, 'password': password},
      options: Options(extra: const <String, dynamic>{'tb_skip_auth': true}),
    );
    return LoginResponse.fromJson(response.data ?? const <String, dynamic>{});
  }

  @override
  Future<TbUserProfile> getCurrentUser() async {
    final response = await _client.get<Map<String, dynamic>>('/api/auth/user');
    return TbUserProfile.fromJson(response.data ?? const <String, dynamic>{});
  }

  @override
  Future<void> logout() async {
    await _client.post<void>('/api/auth/logout');
  }

  @override
  Future<void> requestPasswordReset(String email) async {
    await _client.post<void>(
      '/api/noauth/resetPasswordByEmail',
      data: <String, dynamic>{'email': email},
      options: Options(extra: const <String, dynamic>{'tb_skip_auth': true}),
    );
  }

  @override
  Future<List<TwoFaProviderInfo>> getTwoFaProviders(String preAuthToken) async {
    final response = await _client.get<List<dynamic>>(
      '/api/auth/2fa/providers',
      options: Options(
        headers: <String, dynamic>{'X-Authorization': 'Bearer $preAuthToken'},
        extra: const <String, dynamic>{'tb_skip_auth': true},
      ),
    );
    final list = response.data ?? const [];
    return list
        .whereType<Map<String, dynamic>>()
        .map(TwoFaProviderInfo.fromJson)
        .toList(growable: false);
  }

  @override
  Future<void> sendTwoFaVerificationCode({
    required String preAuthToken,
    required String providerType,
  }) async {
    await _client.post<void>(
      '/api/auth/2fa/verification/send',
      queryParameters: <String, dynamic>{'providerType': providerType},
      options: Options(
        headers: <String, dynamic>{'X-Authorization': 'Bearer $preAuthToken'},
        extra: const <String, dynamic>{'tb_skip_auth': true},
      ),
    );
  }

  @override
  Future<LoginResponse> checkTwoFaVerificationCode({
    required String preAuthToken,
    required String providerType,
    required String verificationCode,
  }) async {
    final response = await _client.post<Map<String, dynamic>>(
      '/api/auth/2fa/verification/check',
      queryParameters: <String, dynamic>{
        'providerType': providerType,
        'verificationCode': verificationCode,
      },
      options: Options(
        headers: <String, dynamic>{'X-Authorization': 'Bearer $preAuthToken'},
        extra: const <String, dynamic>{'tb_skip_auth': true},
      ),
    );
    return LoginResponse.fromJson(response.data ?? const <String, dynamic>{});
  }

  @override
  Future<LoginResponse> authenticateByMfaConfigurationToken(
    String preAuthToken,
  ) async {
    final response = await _client.post<Map<String, dynamic>>(
      '/api/auth/2fa/login',
      options: Options(
        headers: <String, dynamic>{'X-Authorization': 'Bearer $preAuthToken'},
        extra: const <String, dynamic>{'tb_skip_auth': true},
      ),
    );
    return LoginResponse.fromJson(response.data ?? const <String, dynamic>{});
  }

  @override
  Future<LoginResponse> loginByQrSecret(String secret) async {
    final response = await _client.get<Map<String, dynamic>>(
      '/api/noauth/qr/${Uri.encodeComponent(secret)}',
      options: Options(extra: const <String, dynamic>{'tb_skip_auth': true}),
    );
    return LoginResponse.fromJson(response.data ?? const <String, dynamic>{});
  }
}

final class DemoAuthRepository implements AuthRepository {
  @override
  Future<LoginResponse> login(String username, String password) async {
    return const LoginResponse(
      token: 'demo-jwt-token',
      refreshToken: 'demo-refresh-token',
      scope: Authority.tenantAdmin,
    );
  }

  @override
  Future<TbUserProfile> getCurrentUser() async {
    return const TbUserProfile(
      id: 'demo-user-1',
      email: 'tenant@thingsboard.org',
      authority: Authority.tenantAdmin,
      firstName: 'John',
      lastName: 'Doe',
      phone: '+1 415 555 0199',
      homeDashboardId: 'dash-1',
      homeDashboardTitle: 'Smart Office Monitoring',
    );
  }

  @override
  Future<void> logout() async {}

  @override
  Future<void> requestPasswordReset(String email) async {}

  @override
  Future<List<TwoFaProviderInfo>> getTwoFaProviders(
    String preAuthToken,
  ) async => const [TwoFaProviderInfo(type: 'TOTP', isDefault: true)];

  @override
  Future<void> sendTwoFaVerificationCode({
    required String preAuthToken,
    required String providerType,
  }) async {}

  @override
  Future<LoginResponse> checkTwoFaVerificationCode({
    required String preAuthToken,
    required String providerType,
    required String verificationCode,
  }) async {
    return const LoginResponse(
      token: 'demo-jwt-token',
      refreshToken: 'demo-refresh-token',
      scope: Authority.tenantAdmin,
    );
  }

  @override
  Future<LoginResponse> authenticateByMfaConfigurationToken(
    String preAuthToken,
  ) async {
    return const LoginResponse(
      token: 'demo-jwt-token',
      refreshToken: 'demo-refresh-token',
      scope: Authority.tenantAdmin,
    );
  }

  @override
  Future<LoginResponse> loginByQrSecret(String secret) async {
    return const LoginResponse(
      token: 'demo-jwt-token',
      refreshToken: 'demo-refresh-token',
      scope: Authority.tenantAdmin,
    );
  }
}
