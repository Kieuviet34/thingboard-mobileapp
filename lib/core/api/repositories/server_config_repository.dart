import 'package:flutter/foundation.dart';
import 'package:thingsboard_democloud_app/core/api/client/tb_api_client.dart';
import 'package:thingsboard_democloud_app/core/models/auth_models.dart';
import 'package:thingsboard_democloud_app/core/models/tb_failure.dart';

/// Reads public server capabilities, OAuth2 clients, password policies, and version info.
abstract interface class ServerConfigRepository {
  Future<UserPasswordPolicy?> fetchPasswordPolicy();
  Future<List<OAuth2ClientModel>> fetchOAuth2Clients({
    required String pkgName,
    required String platform,
  });
  Future<LoginMobileInfo?> fetchMobileInfo({
    required String pkgName,
    required String platform,
  });
  Future<Map<String, dynamic>?> fetchWhiteLabelParams();
  Future<String?> fetchSystemVersion();
}

final class RestServerConfigRepository implements ServerConfigRepository {
  RestServerConfigRepository({required TbApiClient client}) : _client = client;

  final TbApiClient _client;

  @override
  Future<UserPasswordPolicy?> fetchPasswordPolicy() async {
    try {
      final response = await _client.get<Map<String, dynamic>>(
        '/api/noauth/userPasswordPolicy',
      );
      final data = response.data;
      return data != null ? UserPasswordPolicy.fromJson(data) : null;
    } on TbFailure catch (e) {
      if (e.type == TbFailureType.notFound) return null;
      rethrow;
    }
  }

  @override
  Future<List<OAuth2ClientModel>> fetchOAuth2Clients({
    required String pkgName,
    required String platform,
  }) async {
    try {
      final response = await _client.post<List<dynamic>>(
        '/api/noauth/oauth2Clients',
        queryParameters: <String, dynamic>{
          'pkgName': pkgName,
          'platform': platform,
        },
      );
      final list = response.data ?? const [];
      return list
          .whereType<Map<String, dynamic>>()
          .map(OAuth2ClientModel.fromJson)
          .toList(growable: false);
    } on TbFailure catch (e) {
      if (e.type == TbFailureType.notFound) return const [];
      rethrow;
    }
  }

  @override
  Future<LoginMobileInfo?> fetchMobileInfo({
    required String pkgName,
    required String platform,
  }) async {
    try {
      final response = await _client.get<Map<String, dynamic>>(
        '/api/noauth/mobile',
        queryParameters: <String, dynamic>{
          'pkgName': pkgName,
          'platform': platform,
        },
      );
      final data = response.data;
      return data != null ? LoginMobileInfo.fromJson(data) : null;
    } on TbFailure catch (e) {
      // Confirmed 404 on thingsboard.democloud.xyz — treat as feature unavailable.
      if (e.type == TbFailureType.notFound) return null;
      rethrow;
    }
  }

  @override
  Future<Map<String, dynamic>?> fetchWhiteLabelParams() async {
    try {
      final response = await _client.get<Map<String, dynamic>>(
        '/api/noauth/whiteLabel/loginWhiteLabelParams',
      );
      return response.data;
    } on TbFailure catch (e) {
      // Confirmed 404 on thingsboard.democloud.xyz — treat as feature unavailable.
      if (e.type == TbFailureType.notFound) return null;
      rethrow;
    }
  }

  @override
  Future<String?> fetchSystemVersion() async {
    try {
      final response = await _client.get<Map<String, dynamic>>(
        '/api/system/info',
      );
      return response.data?['version'] as String?;
    } on TbFailure catch (e) {
      if (e.type == TbFailureType.notFound ||
          e.type == TbFailureType.permissionDenied) {
        return null;
      }
      rethrow;
    }
  }
}

final class DemoServerConfigRepository implements ServerConfigRepository {
  @override
  Future<UserPasswordPolicy?> fetchPasswordPolicy() async =>
      const UserPasswordPolicy(minimumLength: 6);

  @override
  Future<List<OAuth2ClientModel>> fetchOAuth2Clients({
    required String pkgName,
    required String platform,
  }) async => const [];

  @override
  Future<LoginMobileInfo?> fetchMobileInfo({
    required String pkgName,
    required String platform,
  }) async => null;

  @override
  Future<Map<String, dynamic>?> fetchWhiteLabelParams() async => null;

  @override
  Future<String?> fetchSystemVersion() async => '4.4.1-DEMO';
}

/// Platform helper used by [ServerConfigController] when probing OAuth2/mobile config.
String resolveMobilePlatformName() {
  return switch (defaultTargetPlatform) {
    TargetPlatform.iOS => 'IOS',
    _ => 'ANDROID',
  };
}
