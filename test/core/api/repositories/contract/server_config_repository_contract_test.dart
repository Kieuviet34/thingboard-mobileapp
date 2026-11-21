import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thingsboard_democloud_app/core/api/client/tb_api_client.dart';
import 'package:thingsboard_democloud_app/core/api/repositories/server_config_repository.dart';
import 'package:thingsboard_democloud_app/core/models/models.dart';

import '../../../../helpers/fake_secure_storage.dart';
import '../../../../helpers/mock_dio_adapter.dart';
import '../../../../helpers/openapi_contract.dart';

/// Contract test: every request `RestServerConfigRepository` sends must exist in
/// the ThingsBoard 4.4.1PAAS OpenAPI, and every response shape must parse correctly.
void main() {
  late MockDioAdapter adapter;
  late RestServerConfigRepository repo;
  final contract = OpenApiContract.load();

  const pkgName = 'com.example.app';

  RequestOptions requestFor(String method, String path) => adapter
      .capturedRequests
      .lastWhere((r) => r.method == method && r.path == path);

  Matcher failureOfType(TbFailureType type) =>
      throwsA(isA<TbFailure>().having((e) => e.type, 'type', type));

  setUp(() {
    adapter = MockDioAdapter();
    repo = RestServerConfigRepository(
      client: TbApiClient(
        baseUrl: 'https://thingsboard.democloud.xyz/',
        storage: FakeSecureStorage(),
        httpClientAdapter: adapter,
      ),
    );
  });

  group('fetchPasswordPolicy', () {
    test(
      'GET /api/noauth/userPasswordPolicy parses UserPasswordPolicy',
      () async {
        adapter.on(
          'GET',
          '/api/noauth/userPasswordPolicy',
          (_) => MockDioAdapter.jsonResponse(<String, dynamic>{
            'minimumLength': 8,
            'maximumLength': 72,
            'minimumUppercaseLetters': 1,
            'minimumLowercaseLetters': 2,
            'minimumDigits': 1,
            'minimumSpecialCharacters': 1,
            'allowWhitespaces': false,
            'forceUserToResetPasswordIfNotValid': false,
            'passwordExpirationPeriodDays': 90,
            'passwordReuseFrequencyDays': 365,
          }),
        );

        final policy = await repo.fetchPasswordPolicy();

        contract.expectAllConform(adapter);
        expect(policy, isNotNull);
        expect(policy!.minimumLength, 8);
        expect(policy.minimumUppercaseLetters, 1);
        expect(policy.minimumLowercaseLetters, 2);
        expect(policy.minimumDigits, 1);
        expect(policy.minimumSpecialCharacters, 1);
        expect(policy.allowWhitespaces, isFalse);
        expect(
          contract.coveredOperations(adapter.capturedRequests),
          contains('GET /api/noauth/userPasswordPolicy'),
        );
      },
    );

    test('404 resolves to null, other errors propagate', () async {
      adapter.on(
        'GET',
        '/api/noauth/userPasswordPolicy',
        (_) => MockDioAdapter.jsonResponse(<String, dynamic>{
          'message': 'Not found',
        }, statusCode: 404),
      );
      expect(await repo.fetchPasswordPolicy(), isNull);

      adapter.on(
        'GET',
        '/api/noauth/userPasswordPolicy',
        (_) => MockDioAdapter.jsonResponse(<String, dynamic>{
          'message': 'boom',
        }, statusCode: 500),
      );
      await expectLater(
        repo.fetchPasswordPolicy(),
        failureOfType(TbFailureType.serverError),
      );
      contract.expectAllConform(adapter);
    });
  });

  group('fetchOAuth2Clients', () {
    test(
      'POST /api/noauth/oauth2Clients sends spec query params (ANDROID and IOS)',
      () async {
        adapter.on(
          'POST',
          '/api/noauth/oauth2Clients',
          (_) => MockDioAdapter.jsonResponse(<dynamic>[
            {
              'name': 'Google',
              'icon': 'google-icon',
              'url': 'https://oauth.example.com/login/google',
            },
          ]),
        );

        final android = await repo.fetchOAuth2Clients(
          pkgName: pkgName,
          platform: 'ANDROID',
        );
        final ios = await repo.fetchOAuth2Clients(
          pkgName: pkgName,
          platform: 'IOS',
        );

        contract.expectAllConform(adapter);
        final queries = adapter.capturedRequests
            .where((r) => r.path == '/api/noauth/oauth2Clients')
            .map((r) => r.queryParameters)
            .toList();
        expect(queries, [
          <String, dynamic>{'pkgName': pkgName, 'platform': 'ANDROID'},
          <String, dynamic>{'pkgName': pkgName, 'platform': 'IOS'},
        ]);
        expect(android.single.name, 'Google');
        expect(android.single.icon, 'google-icon');
        expect(android.single.url, 'https://oauth.example.com/login/google');
        expect(ios, hasLength(1));
        expect(
          contract.coveredOperations(adapter.capturedRequests),
          contains('POST /api/noauth/oauth2Clients'),
        );
      },
    );

    test('404 resolves to empty list, other errors propagate', () async {
      adapter.on(
        'POST',
        '/api/noauth/oauth2Clients',
        (_) => MockDioAdapter.jsonResponse(<String, dynamic>{
          'message': 'Not found',
        }, statusCode: 404),
      );
      expect(
        await repo.fetchOAuth2Clients(pkgName: pkgName, platform: 'ANDROID'),
        isEmpty,
      );

      adapter.on(
        'POST',
        '/api/noauth/oauth2Clients',
        (_) => MockDioAdapter.jsonResponse(<String, dynamic>{
          'message': 'boom',
        }, statusCode: 500),
      );
      await expectLater(
        repo.fetchOAuth2Clients(pkgName: pkgName, platform: 'ANDROID'),
        failureOfType(TbFailureType.serverError),
      );
      contract.expectAllConform(adapter);
    });
  });

  group('fetchMobileInfo', () {
    test(
      'GET /api/noauth/mobile sends spec query params and parses LoginMobileInfo',
      () async {
        adapter.on(
          'GET',
          '/api/noauth/mobile',
          (_) => MockDioAdapter.jsonResponse(<String, dynamic>{
            'oAuth2ClientLoginInfos': [
              {
                'name': 'Google',
                'icon': 'google-icon',
                'url': 'https://oauth.example.com/login/google',
              },
            ],
            'selfRegistrationParams': {
              'title': 'Sign up',
              'showPrivacyPolicy': false,
              'showTermsOfUse': false,
              'fields': <dynamic>[],
            },
            'versionInfo': {'minVersion': '1.0.0', 'latestVersion': '1.2.0'},
          }),
        );

        final info = await repo.fetchMobileInfo(
          pkgName: pkgName,
          platform: 'ANDROID',
        );

        contract.expectAllConform(adapter);
        expect(
          requestFor('GET', '/api/noauth/mobile').queryParameters,
          <String, dynamic>{'pkgName': pkgName, 'platform': 'ANDROID'},
        );
        expect(info, isNotNull);
        expect(info!.oAuth2Clients.single.name, 'Google');
        expect(info.oAuth2Clients.single.icon, 'google-icon');
        expect(info.selfRegistrationEnabled, isTrue);
        expect(
          contract.coveredOperations(adapter.capturedRequests),
          contains('GET /api/noauth/mobile'),
        );
      },
    );

    test('404 resolves to null, other errors propagate', () async {
      adapter.on(
        'GET',
        '/api/noauth/mobile',
        (_) => MockDioAdapter.jsonResponse(<String, dynamic>{
          'message': 'Not found',
        }, statusCode: 404),
      );
      expect(
        await repo.fetchMobileInfo(pkgName: pkgName, platform: 'IOS'),
        isNull,
      );

      adapter.on(
        'GET',
        '/api/noauth/mobile',
        (_) => MockDioAdapter.jsonResponse(<String, dynamic>{
          'message': 'boom',
        }, statusCode: 500),
      );
      await expectLater(
        repo.fetchMobileInfo(pkgName: pkgName, platform: 'IOS'),
        failureOfType(TbFailureType.serverError),
      );
      contract.expectAllConform(adapter);
      expect(
        requestFor('GET', '/api/noauth/mobile').queryParameters,
        <String, dynamic>{'pkgName': pkgName, 'platform': 'IOS'},
      );
    });
  });

  group('fetchWhiteLabelParams', () {
    test(
      'GET /api/noauth/whiteLabel/loginWhiteLabelParams returns the params map',
      () async {
        adapter.on(
          'GET',
          '/api/noauth/whiteLabel/loginWhiteLabelParams',
          (_) => MockDioAdapter.jsonResponse(<String, dynamic>{
            'appTitle': 'DemoCloud',
            'whiteLabelingEnabled': true,
            'primaryColorPanels': false,
          }),
        );

        final params = await repo.fetchWhiteLabelParams();

        contract.expectAllConform(adapter);
        expect(params, isNotNull);
        expect(params!['appTitle'], 'DemoCloud');
        expect(params['whiteLabelingEnabled'], isTrue);
        expect(
          contract.coveredOperations(adapter.capturedRequests),
          contains('GET /api/noauth/whiteLabel/loginWhiteLabelParams'),
        );
      },
    );

    test('404 resolves to null, other errors propagate', () async {
      adapter.on(
        'GET',
        '/api/noauth/whiteLabel/loginWhiteLabelParams',
        (_) => MockDioAdapter.jsonResponse(<String, dynamic>{
          'message': 'Not found',
        }, statusCode: 404),
      );
      expect(await repo.fetchWhiteLabelParams(), isNull);

      adapter.on(
        'GET',
        '/api/noauth/whiteLabel/loginWhiteLabelParams',
        (_) => MockDioAdapter.jsonResponse(<String, dynamic>{
          'message': 'boom',
        }, statusCode: 500),
      );
      await expectLater(
        repo.fetchWhiteLabelParams(),
        failureOfType(TbFailureType.serverError),
      );
      contract.expectAllConform(adapter);
    });
  });

  group('fetchSystemVersion', () {
    test('GET /api/system/info returns the version string', () async {
      adapter.on(
        'GET',
        '/api/system/info',
        (_) => MockDioAdapter.jsonResponse(<String, dynamic>{
          'version': '4.4.1PAAS',
          'type': 'PAAS',
          'name': 'thingsboard',
          'artifact': 'tb-pe',
        }),
      );

      final version = await repo.fetchSystemVersion();

      contract.expectAllConform(adapter);
      expect(version, '4.4.1PAAS');
      expect(
        contract.coveredOperations(adapter.capturedRequests),
        contains('GET /api/system/info'),
      );
    });

    test('404 and 403 resolve to null, other errors propagate', () async {
      adapter.on(
        'GET',
        '/api/system/info',
        (_) => MockDioAdapter.jsonResponse(<String, dynamic>{
          'message': 'Not found',
        }, statusCode: 404),
      );
      expect(await repo.fetchSystemVersion(), isNull);

      adapter.on(
        'GET',
        '/api/system/info',
        (_) => MockDioAdapter.jsonResponse(<String, dynamic>{
          'message': 'Forbidden',
        }, statusCode: 403),
      );
      expect(await repo.fetchSystemVersion(), isNull);

      adapter.on(
        'GET',
        '/api/system/info',
        (_) => MockDioAdapter.jsonResponse(<String, dynamic>{
          'message': 'boom',
        }, statusCode: 500),
      );
      await expectLater(
        repo.fetchSystemVersion(),
        failureOfType(TbFailureType.serverError),
      );
      contract.expectAllConform(adapter);
    });
  });
}
