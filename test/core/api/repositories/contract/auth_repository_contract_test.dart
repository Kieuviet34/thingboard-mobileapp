import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thingsboard_democloud_app/core/api/client/tb_api_client.dart';
import 'package:thingsboard_democloud_app/core/api/repositories/auth_repository.dart';
import 'package:thingsboard_democloud_app/core/models/models.dart';

import '../../../../helpers/fake_secure_storage.dart';
import '../../../../helpers/mock_dio_adapter.dart';
import '../../../../helpers/openapi_contract.dart';

/// Contract test: every request `RestAuthRepository` sends must exist in the
/// ThingsBoard 4.4.1PAAS OpenAPI, and every response shape must parse correctly.
void main() {
  late MockDioAdapter adapter;
  late RestAuthRepository repo;
  final contract = OpenApiContract.load();

  // Obviously fake credentials and tokens only.
  const username = 'user@example.com';
  const password = 'not-a-real-password';

  RequestOptions requestFor(String method, String path) => adapter
      .capturedRequests
      .lastWhere((r) => r.method == method && r.path == path);

  setUp(() {
    adapter = MockDioAdapter();
    repo = RestAuthRepository(
      client: TbApiClient(
        baseUrl: 'https://thingsboard.democloud.xyz/',
        storage: FakeSecureStorage(),
        httpClientAdapter: adapter,
      ),
    );
  });

  test(
    'login sends spec LoginRequest body and parses JwtPair (TENANT_ADMIN)',
    () async {
      adapter.on(
        'POST',
        '/api/auth/login',
        (_) => MockDioAdapter.jsonResponse(<String, dynamic>{
          'token': 'jwt-1',
          'refreshToken': 'refresh-1',
          'scope': 'TENANT_ADMIN',
        }),
      );

      final response = await repo.login(username, password);

      contract.expectAllConform(adapter);
      expect(requestFor('POST', '/api/auth/login').data, <String, dynamic>{
        'username': username,
        'password': password,
      });
      expect(response.token, 'jwt-1');
      expect(response.refreshToken, 'refresh-1');
      expect(response.scope, Authority.tenantAdmin);
      expect(
        contract.coveredOperations(adapter.capturedRequests),
        contains('POST /api/auth/login'),
      );
    },
  );

  test(
    'login parses PRE_VERIFICATION_TOKEN and MFA_CONFIGURATION_TOKEN scopes',
    () async {
      adapter
        ..enqueue(
          'POST',
          '/api/auth/login',
          (_) => MockDioAdapter.jsonResponse(<String, dynamic>{
            'token': 'pre-verify-1',
            'scope': 'PRE_VERIFICATION_TOKEN',
          }),
        )
        ..enqueue(
          'POST',
          '/api/auth/login',
          (_) => MockDioAdapter.jsonResponse(<String, dynamic>{
            'token': 'mfa-config-1',
            'scope': 'MFA_CONFIGURATION_TOKEN',
          }),
        );

      final pending = await repo.login(username, password);
      final configuration = await repo.login(username, password);

      contract.expectAllConform(adapter);
      expect(pending.token, 'pre-verify-1');
      expect(pending.scope, Authority.preVerificationToken);
      expect(pending.refreshToken, isNull);
      expect(configuration.token, 'mfa-config-1');
      expect(configuration.scope, Authority.mfaConfigurationToken);
    },
  );

  test('getCurrentUser calls GET /api/auth/user and parses User', () async {
    adapter.on(
      'GET',
      '/api/auth/user',
      (_) => MockDioAdapter.jsonResponse(<String, dynamic>{
        'id': {'entityType': 'USER', 'id': 'u-1'},
        'tenantId': {'entityType': 'TENANT', 'id': 't-1'},
        'createdTime': 1700000000000,
        'email': username,
        'authority': 'TENANT_ADMIN',
        'firstName': 'Ann',
        'lastName': 'Lee',
        'phone': '+1 555 0100',
      }),
    );

    final user = await repo.getCurrentUser();

    contract.expectAllConform(adapter);
    expect(user.id, 'u-1');
    expect(user.email, username);
    expect(user.authority, Authority.tenantAdmin);
    expect(user.firstName, 'Ann');
    expect(user.lastName, 'Lee');
    expect(
      contract.coveredOperations(adapter.capturedRequests),
      contains('GET /api/auth/user'),
    );
  });

  test('logout calls POST /api/auth/logout without a body', () async {
    adapter.on(
      'POST',
      '/api/auth/logout',
      (_) => MockDioAdapter.emptyResponse(),
    );

    await repo.logout();

    contract.expectAllConform(adapter);
    expect(requestFor('POST', '/api/auth/logout').data, isNull);
    expect(
      contract.coveredOperations(adapter.capturedRequests),
      contains('POST /api/auth/logout'),
    );
  });

  test(
    'requestPasswordReset sends spec ResetPasswordEmailRequest on noauth path',
    () async {
      adapter.on(
        'POST',
        '/api/noauth/resetPasswordByEmail',
        (_) => MockDioAdapter.emptyResponse(),
      );

      await repo.requestPasswordReset(username);

      contract.expectAllConform(adapter);
      expect(
        requestFor('POST', '/api/noauth/resetPasswordByEmail').data,
        <String, dynamic>{'email': username},
      );
      expect(
        contract.coveredOperations(adapter.capturedRequests),
        contains('POST /api/noauth/resetPasswordByEmail'),
      );
    },
  );

  test('2FA providers list parses TwoFaProviderInfo entries', () async {
    adapter.on(
      'GET',
      '/api/auth/2fa/providers',
      (_) => MockDioAdapter.jsonResponse(<dynamic>[
        {'type': 'TOTP', 'default': true},
        {
          'type': 'SMS',
          'default': false,
          'contact': '+1 *** *** 0100',
          'minVerificationCodeSendPeriod': 30,
        },
      ]),
    );

    final providers = await repo.getTwoFaProviders('pre-verify-1');

    contract.expectAllConform(adapter);
    expect(providers.map((p) => p.type), ['TOTP', 'SMS']);
    expect(providers[0].isDefault, isTrue);
    expect(providers[0].contact, isNull);
    expect(providers[1].isDefault, isFalse);
    expect(providers[1].contact, '+1 *** *** 0100');
    expect(
      requestFor('GET', '/api/auth/2fa/providers').headers['X-Authorization'],
      'Bearer pre-verify-1',
    );
    expect(
      contract.coveredOperations(adapter.capturedRequests),
      contains('GET /api/auth/2fa/providers'),
    );
  });

  test('2FA send and check use spec query params and parse JwtPair', () async {
    adapter
      ..on(
        'POST',
        '/api/auth/2fa/verification/send',
        (_) => MockDioAdapter.emptyResponse(),
      )
      ..on(
        'POST',
        '/api/auth/2fa/verification/check',
        (_) => MockDioAdapter.jsonResponse(<String, dynamic>{
          'token': 'jwt-2',
          'refreshToken': 'refresh-2',
          'scope': 'TENANT_ADMIN',
        }),
      );

    await repo.sendTwoFaVerificationCode(
      preAuthToken: 'pre-verify-1',
      providerType: 'SMS',
    );
    final session = await repo.checkTwoFaVerificationCode(
      preAuthToken: 'pre-verify-1',
      providerType: 'SMS',
      verificationCode: '123456',
    );

    contract.expectAllConform(adapter);
    expect(
      requestFor('POST', '/api/auth/2fa/verification/send').queryParameters,
      <String, dynamic>{'providerType': 'SMS'},
    );
    expect(
      requestFor('POST', '/api/auth/2fa/verification/check').queryParameters,
      <String, dynamic>{'providerType': 'SMS', 'verificationCode': '123456'},
    );
    expect(session.token, 'jwt-2');
    expect(session.refreshToken, 'refresh-2');
    expect(session.scope, Authority.tenantAdmin);
    expect(
      contract.coveredOperations(adapter.capturedRequests),
      containsAll(<String>[
        'POST /api/auth/2fa/verification/send',
        'POST /api/auth/2fa/verification/check',
      ]),
    );
  });

  test(
    '2FA configuration-token login calls POST /api/auth/2fa/login',
    () async {
      adapter.on(
        'POST',
        '/api/auth/2fa/login',
        (_) => MockDioAdapter.jsonResponse(<String, dynamic>{
          'token': 'jwt-3',
          'refreshToken': 'refresh-3',
          'scope': 'TENANT_ADMIN',
        }),
      );

      final session = await repo.authenticateByMfaConfigurationToken(
        'mfa-config-1',
      );

      contract.expectAllConform(adapter);
      expect(
        requestFor('POST', '/api/auth/2fa/login').headers['X-Authorization'],
        'Bearer mfa-config-1',
      );
      expect(session.token, 'jwt-3');
      expect(session.scope, Authority.tenantAdmin);
      expect(
        contract.coveredOperations(adapter.capturedRequests),
        contains('POST /api/auth/2fa/login'),
      );
    },
  );

  test('QR secret login puts the secret in the spec path', () async {
    adapter.on(
      'GET',
      '/api/noauth/qr/qr-secret-1',
      (_) => MockDioAdapter.jsonResponse(<String, dynamic>{
        'token': 'jwt-4',
        'refreshToken': 'refresh-4',
        'scope': 'TENANT_ADMIN',
      }),
    );

    final session = await repo.loginByQrSecret('qr-secret-1');

    contract.expectAllConform(adapter);
    expect(session.token, 'jwt-4');
    expect(session.refreshToken, 'refresh-4');
    expect(session.scope, Authority.tenantAdmin);
    expect(
      contract.coveredOperations(adapter.capturedRequests),
      contains('GET /api/noauth/qr/{secret}'),
    );
  });

  test(
    'QR secret with reserved characters is URL-encoded in the path',
    () async {
      adapter.on(
        'GET',
        '/api/noauth/qr/a%2Fb%2Bc%3D',
        (_) => MockDioAdapter.jsonResponse(<String, dynamic>{
          'token': 'jwt-5',
          'refreshToken': 'refresh-5',
          'scope': 'TENANT_ADMIN',
        }),
      );

      final session = await repo.loginByQrSecret('a/b+c=');

      expect(session.token, 'jwt-5');
      expect(
        adapter.capturedRequests.single.path,
        '/api/noauth/qr/a%2Fb%2Bc%3D',
      );
      contract.expectAllConform(adapter);
    },
  );
}
