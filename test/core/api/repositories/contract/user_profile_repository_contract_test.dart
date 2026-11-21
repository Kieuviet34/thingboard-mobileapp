import 'package:flutter_test/flutter_test.dart';
import 'package:thingsboard_democloud_app/core/api/client/tb_api_client.dart';
import 'package:thingsboard_democloud_app/core/api/repositories/user_profile_repository.dart';
import 'package:thingsboard_democloud_app/core/models/models.dart';

import '../../../../helpers/fake_secure_storage.dart';
import '../../../../helpers/mock_dio_adapter.dart';
import '../../../../helpers/openapi_contract.dart';

/// Contract test: every request `RestUserProfileRepository` sends must exist in the
/// ThingsBoard 4.4.1PAAS OpenAPI, and every response shape must parse correctly.
void main() {
  late MockDioAdapter adapter;
  late RestUserProfileRepository repo;
  final contract = OpenApiContract.load();

  const userJson = <String, dynamic>{
    'id': {'entityType': 'USER', 'id': 'u-1'},
    'createdTime': 1700000000000,
    'tenantId': {'entityType': 'TENANT', 'id': 't-1'},
    'customerId': {'entityType': 'CUSTOMER', 'id': 'c-1'},
    'email': 'ann@example.com',
    'authority': 'TENANT_ADMIN',
    'firstName': 'Ann',
    'lastName': 'Lee',
    'phone': '+84 900 000 000',
    'name': 'ann@example.com',
    'additionalInfo': {
      'lang': 'vi_VN',
      'unitSystem': 'IMPERIAL',
      'homeDashboardId': 'dash-1',
      'homeDashboardHideToolbar': false,
    },
  };

  setUp(() {
    adapter = MockDioAdapter();
    repo = RestUserProfileRepository(
      client: TbApiClient(
        baseUrl: 'https://thingsboard.democloud.xyz/',
        storage: FakeSecureStorage(),
        httpClientAdapter: adapter,
      ),
    );
  });

  test(
    'getUserProfile GETs /api/auth/user and parses User into the profile',
    () async {
      adapter.on(
        'GET',
        '/api/auth/user',
        (_) => MockDioAdapter.jsonResponse(userJson),
      );

      final profile = await repo.getUserProfile();

      contract.expectAllConform(adapter);
      expect(profile.id, 'u-1');
      expect(profile.email, 'ann@example.com');
      expect(profile.authority, Authority.tenantAdmin);
      expect(profile.displayName, 'Ann Lee');
      expect(profile.tenantId, 't-1');
      expect(profile.customerId, 'c-1');
      expect(profile.phone, '+84 900 000 000');
      expect(profile.language, 'vi_VN');
      expect(profile.unitSystem, 'IMPERIAL');
      expect(profile.homeDashboardId, 'dash-1');
      expect(profile.hideHomeDashboardToolbar, isFalse);
      expect(
        contract.coveredOperations(adapter.capturedRequests),
        contains('GET /api/auth/user'),
      );
    },
  );

  test(
    'updateUserProfile POSTs /api/user with a body made only of User fields',
    () async {
      adapter.on(
        'POST',
        '/api/user',
        (_) => MockDioAdapter.jsonResponse({...userJson, 'firstName': 'Anna'}),
      );

      final saved = await repo.updateUserProfile(
        TbUserProfile.fromJson(userJson).copyWith(firstName: 'Anna'),
      );

      contract.expectAllConform(adapter);
      expect(adapter.capturedRequests.single.data, {
        'id': {'entityType': 'USER', 'id': 'u-1'},
        'tenantId': {'entityType': 'TENANT', 'id': 't-1'},
        'customerId': {'entityType': 'CUSTOMER', 'id': 'c-1'},
        'email': 'ann@example.com',
        'authority': 'TENANT_ADMIN',
        'firstName': 'Anna',
        'lastName': 'Lee',
        'phone': '+84 900 000 000',
        'additionalInfo': {
          'lang': 'vi_VN',
          'unitSystem': 'IMPERIAL',
          'homeDashboardId': 'dash-1',
          'homeDashboardHideToolbar': false,
        },
      });
      expect(saved.firstName, 'Anna');
      expect(saved.id, 'u-1');
      expect(
        contract.coveredOperations(adapter.capturedRequests),
        contains('POST /api/user'),
      );
    },
  );

  test(
    'getGeneralSettings returns the JSON node, and an empty map on 404',
    () async {
      adapter
        ..enqueue(
          'GET',
          '/api/user/settings/general',
          (_) => MockDioAdapter.jsonResponse({'status': 404}, statusCode: 404),
        )
        ..on(
          'GET',
          '/api/user/settings/general',
          (_) => MockDioAdapter.jsonResponse({
            'theme': 'dark',
            'mobileNotifications': true,
          }),
        );

      final missing = await repo.getGeneralSettings();
      final settings = await repo.getGeneralSettings();

      contract.expectAllConform(adapter);
      expect(missing, isEmpty);
      expect(settings, {'theme': 'dark', 'mobileNotifications': true});
      expect(
        contract.coveredOperations(adapter.capturedRequests),
        contains('GET /api/user/settings/general'),
      );
    },
  );

  test(
    'updateGeneralSettings PUTs /api/user/settings/general with the settings map',
    () async {
      adapter.on(
        'PUT',
        '/api/user/settings/general',
        (_) => MockDioAdapter.emptyResponse(),
      );

      await repo.updateGeneralSettings({
        'theme': 'dark',
        'mobileNotifications': true,
      });

      contract.expectAllConform(adapter);
      expect(adapter.capturedRequests.single.data, {
        'theme': 'dark',
        'mobileNotifications': true,
      });
      expect(
        contract.coveredOperations(adapter.capturedRequests),
        contains('PUT /api/user/settings/general'),
      );
    },
  );

  test(
    'changePassword POSTs ChangePasswordRequest fields and parses the JwtPair reply',
    () async {
      adapter.on(
        'POST',
        '/api/auth/changePassword',
        (_) => MockDioAdapter.jsonResponse({
          'token': 'jwt-new',
          'refreshToken': 'refresh-new',
          'scope': 'TENANT_ADMIN',
        }),
      );

      final login = await repo.changePassword(
        currentPassword: 'old-pass',
        newPassword: 'new-pass-123',
      );

      contract.expectAllConform(adapter);
      expect(adapter.capturedRequests.single.data, {
        'currentPassword': 'old-pass',
        'newPassword': 'new-pass-123',
      });
      expect(login.token, 'jwt-new');
      expect(login.refreshToken, 'refresh-new');
      expect(login.scope, Authority.tenantAdmin);
      expect(
        contract.coveredOperations(adapter.capturedRequests),
        contains('POST /api/auth/changePassword'),
      );
    },
  );
}
