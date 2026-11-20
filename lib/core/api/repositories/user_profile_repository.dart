import 'package:thingsboard_democloud_app/core/api/client/tb_api_client.dart';
import 'package:thingsboard_democloud_app/core/mock/mock_data.dart';
import 'package:thingsboard_democloud_app/core/models/auth_models.dart';
import 'package:thingsboard_democloud_app/core/models/entity_id.dart';
import 'package:thingsboard_democloud_app/core/models/tb_failure.dart';
import 'package:thingsboard_democloud_app/core/models/user_models.dart';

/// User profile, general/mobile preferences, and password-change boundary.
abstract interface class UserProfileRepository {
  Future<TbUserProfile> getUserProfile();
  Future<TbUserProfile> updateUserProfile(TbUserProfile profile);
  Future<Map<String, dynamic>> getGeneralSettings();
  Future<void> updateGeneralSettings(Map<String, dynamic> settings);
  Future<LoginResponse> changePassword({
    required String currentPassword,
    required String newPassword,
  });
}

final class RestUserProfileRepository implements UserProfileRepository {
  RestUserProfileRepository({required TbApiClient client}) : _client = client;

  final TbApiClient _client;

  @override
  Future<TbUserProfile> getUserProfile() async {
    final response = await _client.get<Map<String, dynamic>>('/api/auth/user');
    return TbUserProfile.fromJson(response.data ?? const <String, dynamic>{});
  }

  @override
  Future<TbUserProfile> updateUserProfile(TbUserProfile profile) async {
    final response = await _client.post<Map<String, dynamic>>(
      '/api/user',
      data: profile.toUserPayload(),
    );
    return TbUserProfile.fromJson(response.data ?? const <String, dynamic>{});
  }

  @override
  Future<Map<String, dynamic>> getGeneralSettings() async {
    try {
      final response = await _client.get<Map<String, dynamic>>(
        '/api/user/settings/general',
      );
      return response.data ?? const <String, dynamic>{};
    } on TbFailure catch (e) {
      if (e.type == TbFailureType.notFound) return const {};
      rethrow;
    }
  }

  @override
  Future<void> updateGeneralSettings(Map<String, dynamic> settings) async {
    await _client.put<void>('/api/user/settings/general', data: settings);
  }

  @override
  Future<LoginResponse> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final response = await _client.post<Map<String, dynamic>>(
      '/api/auth/changePassword',
      data: <String, dynamic>{
        'currentPassword': currentPassword,
        'newPassword': newPassword,
      },
    );
    return LoginResponse.fromJson(response.data ?? const <String, dynamic>{});
  }
}

final class DemoUserProfileRepository implements UserProfileRepository {
  DemoUserProfileRepository(MockUserProfile seed)
    : _profile = TbUserProfile(
        id: 'demo-user-1',
        email: seed.email,
        authority: Authority.tenantAdmin,
        firstName: seed.firstName,
        lastName: seed.lastName,
        phone: seed.phone,
        language: seed.language,
        unitSystem: seed.unitSystem,
        homeDashboardId: 'dash-1',
        homeDashboardTitle: seed.homeDashboardTitle,
        hideHomeDashboardToolbar: seed.hideHomeDashboardToolbar,
      );

  TbUserProfile _profile;
  Map<String, dynamic> _generalSettings = Map<String, dynamic>.from(
    demoUserGeneralSettings,
  );

  @override
  Future<TbUserProfile> getUserProfile() async => _profile;

  @override
  Future<TbUserProfile> updateUserProfile(TbUserProfile profile) async {
    _profile = profile;
    return _profile;
  }

  @override
  Future<Map<String, dynamic>> getGeneralSettings() async =>
      Map<String, dynamic>.unmodifiable(_generalSettings);

  @override
  Future<void> updateGeneralSettings(Map<String, dynamic> settings) async {
    _generalSettings = Map<String, dynamic>.from(settings);
  }

  @override
  Future<LoginResponse> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    return const LoginResponse(
      token: 'demo-jwt-updated',
      refreshToken: 'demo-refresh-updated',
      scope: Authority.tenantAdmin,
    );
  }
}
