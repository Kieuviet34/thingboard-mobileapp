import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:thingsboard_democloud_app/core/api/client/tb_secure_storage.dart';
import 'package:thingsboard_democloud_app/core/api/controllers/auth_controller.dart';
import 'package:thingsboard_democloud_app/core/api/controllers/server_config_controller.dart';
import 'package:thingsboard_democloud_app/core/models/models.dart';

import '../../../helpers/fake_app_preferences.dart';
import '../../../helpers/fake_secure_storage.dart';
import '../../../helpers/fake_ws_channel.dart';
import '../../../helpers/mock_dio_adapter.dart';
import '../../../helpers/test_container.dart';

String _jwtFor({
  Duration expiresIn = const Duration(hours: 2),
  String authority = 'TENANT_ADMIN',
}) {
  final exp = DateTime.now().add(expiresIn).millisecondsSinceEpoch ~/ 1000;
  final h = base64Url.encode(utf8.encode('{"alg":"HS512"}'));
  final p = base64Url.encode(
    utf8.encode(
      '{"sub":"tenant@tb.io","userId":"u-1","scopes":["$authority"],"exp":$exp}',
    ),
  );
  return '$h.$p.sig';
}

void main() {
  late MockDioAdapter adapter;
  late FakeSecureStorage storage;
  late FakeAppPreferences prefs;
  late List<FakeWebSocketChannel> wsChannels;
  late ProviderContainer container;

  setUp(() {
    adapter = MockDioAdapter();
    storage = FakeSecureStorage();
    prefs = FakeAppPreferences();
    wsChannels = [];

    adapter.on(
      'GET',
      '/api/noauth/userPasswordPolicy',
      (_) => MockDioAdapter.jsonResponse({'minimumLength': 6}),
    );
    adapter.on(
      'POST',
      '/api/noauth/oauth2Clients',
      (_) => MockDioAdapter.jsonResponse([]),
    );
    adapter.on(
      'GET',
      '/api/system/info',
      (_) => MockDioAdapter.jsonResponse({'version': '4.4.1PE'}),
    );
    adapter.on(
      'GET',
      '/api/auth/user',
      (_) => MockDioAdapter.jsonResponse({
        'id': {'entityType': 'USER', 'id': 'u-1'},
        'email': 'tenant@tb.io',
        'authority': 'TENANT_ADMIN',
        'firstName': 'John',
        'lastName': 'Doe',
      }),
    );

    container = createTestContainer(
      overrides: [
        tbStorageProvider.overrideWithValue(storage),
        tbAppPreferencesProvider.overrideWithValue(prefs),
        tbHttpClientAdapterProvider.overrideWithValue(adapter),
        wsChannelFactoryProvider.overrideWithValue((_) {
          final ch = FakeWebSocketChannel();
          wsChannels.add(ch);
          return ch;
        }),
      ],
    );
  });

  group('AuthController & ServerConfigController', () {
    test(
      'login handles normal JWT, PRE_VERIFICATION_TOKEN, and MFA_CONFIGURATION_TOKEN distinctly',
      () async {
        final initialState = await container.read(authProvider.future);
        expect(initialState, isA<AuthUnauthenticated>());

        // 1. PRE_VERIFICATION_TOKEN -> AuthMfaVerificationRequired -> verifyTwoFa -> Authenticated
        adapter.enqueue(
          'POST',
          '/api/auth/login',
          (_) => MockDioAdapter.jsonResponse({
            'token': 'pre-verify-jwt',
            'refreshToken': null,
            'scope': 'PRE_VERIFICATION_TOKEN',
          }),
        );
        adapter.on(
          'GET',
          '/api/auth/2fa/providers',
          (_) => MockDioAdapter.jsonResponse([
            {'type': 'TOTP', 'default': true},
          ]),
        );
        adapter.on(
          'POST',
          '/api/auth/2fa/verification/check',
          (_) => MockDioAdapter.jsonResponse({
            'token': _jwtFor(),
            'refreshToken': 'refresh-after-2fa',
          }),
        );

        await container.read(authProvider.notifier).login('a@b.com', 'secret');
        final mfaState = container.read(authProvider).valueOrNull;
        expect(mfaState, isA<AuthMfaVerificationRequired>());
        expect(
          (mfaState as AuthMfaVerificationRequired).providers.single.type,
          'TOTP',
        );

        await container
            .read(authProvider.notifier)
            .verifyTwoFa(providerType: 'TOTP', verificationCode: '123456');
        expect(
          container.read(authProvider).valueOrNull,
          isA<AuthAuthenticated>(),
        );
        expect(
          await storage.read(TbStorageKeys.refreshToken),
          'refresh-after-2fa',
        );

        // 2. MFA_CONFIGURATION_TOKEN -> AuthMfaConfigurationRequired -> cancelMfa / completeMfaConfiguration
        adapter.enqueue(
          'POST',
          '/api/auth/login',
          (_) => MockDioAdapter.jsonResponse({
            'token': 'mfa-config-jwt',
            'scope': 'MFA_CONFIGURATION_TOKEN',
          }),
        );
        adapter.on(
          'POST',
          '/api/auth/2fa/login',
          (_) => MockDioAdapter.jsonResponse({
            'token': _jwtFor(),
            'refreshToken': 'refresh-after-mfa-setup',
          }),
        );

        await container.read(authProvider.notifier).login('a@b.com', 'secret');
        expect(
          container.read(authProvider).valueOrNull,
          isA<AuthMfaConfigurationRequired>(),
        );

        await container.read(authProvider.notifier).completeMfaConfiguration();
        expect(
          container.read(authProvider).valueOrNull,
          isA<AuthAuthenticated>(),
        );

        await container.read(authProvider.notifier).login('a@b.com', 'secret');
        // wait: second login needs another queued response; cancelMfa test:
        adapter.enqueue(
          'POST',
          '/api/auth/login',
          (_) => MockDioAdapter.jsonResponse({
            'token': 'mfa-config-jwt-2',
            'scope': 'MFA_CONFIGURATION_TOKEN',
          }),
        );
        await container.read(authProvider.notifier).login('a@b.com', 'secret');
        container.read(authProvider.notifier).cancelMfa();
        expect(
          container.read(authProvider).valueOrNull,
          isA<AuthUnauthenticated>(),
        );
      },
    );

    test(
      'QR login, OAuth2 callback, Demo mode switch, and switchServerUrl isolate state',
      () async {
        await container.read(authProvider.future);

        adapter.on(
          'GET',
          '/api/noauth/qr/qr-secret-1',
          (_) => MockDioAdapter.jsonResponse({
            'token': _jwtFor(),
            'refreshToken': 'qr-refresh',
          }),
        );

        await container
            .read(authProvider.notifier)
            .loginWithQrSecret('qr-secret-1');
        final qrAuth = container.read(authProvider).valueOrNull;
        expect(qrAuth, isA<AuthAuthenticated>());
        expect((qrAuth as AuthAuthenticated).mode, SessionMode.live);

        // Switch host atomically clears tokens, bumps sessionGeneration, and signs out.
        final prevGen = container.read(serverConfigProvider).sessionGeneration;
        await container
            .read(serverConfigProvider.notifier)
            .switchServerUrl('https://custom.tb.io');
        expect(
          container.read(serverConfigProvider).baseUrl,
          'https://custom.tb.io/',
        );
        expect(
          container.read(serverConfigProvider).sessionGeneration,
          greaterThan(prevGen),
        );
        expect(await storage.read(TbStorageKeys.accessToken), isNull);
        expect(
          container.read(authProvider).valueOrNull,
          isA<AuthUnauthenticated>(),
        );

        // OAuth2 callback login
        await container
            .read(authProvider.notifier)
            .completeOAuth2(
              accessToken: _jwtFor(),
              refreshToken: 'oauth-refresh',
            );
        expect(
          container.read(authProvider).valueOrNull,
          isA<AuthAuthenticated>(),
        );

        // Demo mode login isolates live tokens and switches mode to demo
        await container.read(authProvider.notifier).loginDemo();
        final demoAuth = container.read(authProvider).valueOrNull;
        expect(demoAuth, isA<AuthAuthenticated>());
        expect((demoAuth as AuthAuthenticated).mode, SessionMode.demo);
        expect(await storage.read(TbStorageKeys.accessToken), isNull);

        await container.read(authProvider.notifier).logout();
        expect(
          container.read(authProvider).valueOrNull,
          isA<AuthUnauthenticated>(),
        );
      },
    );
  });
}
