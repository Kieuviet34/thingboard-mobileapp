import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:thingsboard_democloud_app/config/routes/router.dart';
import 'package:thingsboard_democloud_app/core/api/controllers/auth_controller.dart';
import 'package:thingsboard_democloud_app/core/api/controllers/server_config_controller.dart';
import 'package:thingsboard_democloud_app/core/models/models.dart';
import 'package:thingsboard_democloud_app/main.dart';

import '../helpers/fake_app_preferences.dart';
import '../helpers/fake_secure_storage.dart';
import '../helpers/fake_ws_channel.dart';
import '../helpers/mock_dio_adapter.dart';

String _testJwt() {
  final exp =
      DateTime.now().add(const Duration(hours: 2)).millisecondsSinceEpoch ~/
      1000;
  final h = base64Url.encode(utf8.encode('{"alg":"HS512"}'));
  final p = base64Url.encode(
    utf8.encode(
      '{"sub":"tenant@tb.io","userId":"u-1","scopes":["TENANT_ADMIN"],"exp":$exp}',
    ),
  );
  return '$h.$p.sig';
}

void main() {
  late MockDioAdapter adapter;
  late FakeSecureStorage storage;
  late FakeAppPreferences prefs;

  setUp(() {
    adapter = MockDioAdapter();
    storage = FakeSecureStorage();
    prefs = FakeAppPreferences();

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
        'firstName': 'Tenant',
        'lastName': 'Admin',
      }),
    );
  });

  List<Override> buildOverrides() => [
    tbStorageProvider.overrideWithValue(storage),
    tbAppPreferencesProvider.overrideWithValue(prefs),
    tbHttpClientAdapterProvider.overrideWithValue(adapter),
    wsChannelFactoryProvider.overrideWithValue((_) => FakeWebSocketChannel()),
  ];

  group('tbAuthRedirect pure redirect matrix', () {
    test(
      'redirects unauthenticated protected paths to /login with from param',
      () {
        const unauth = AsyncData<AuthState>(AuthUnauthenticated());

        expect(
          tbAuthRedirect(auth: unauth, uri: Uri.parse('/home')),
          AppRoutes.login,
        );
        expect(
          tbAuthRedirect(auth: unauth, uri: Uri.parse('/alarms')),
          '/login?from=%2Falarms',
        );
        expect(
          tbAuthRedirect(auth: unauth, uri: Uri.parse('/devices/deviceList')),
          '/login?from=%2Fdevices%2FdeviceList',
        );
        expect(tbAuthRedirect(auth: unauth, uri: Uri.parse('/login')), isNull);
        expect(
          tbAuthRedirect(
            auth: unauth,
            uri: Uri.parse('/login/resetPasswordRequest'),
          ),
          isNull,
        );
        expect(
          tbAuthRedirect(auth: unauth, uri: Uri.parse('/qrCodeScan')),
          isNull,
        );
      },
    );

    test(
      'routes PRE_VERIFICATION_TOKEN to /login/2fa and MFA_CONFIGURATION_TOKEN to /login/2fa-setup',
      () {
        const mfaVerify = AsyncData<AuthState>(
          AuthMfaVerificationRequired(
            preAuthToken: 'pre-token',
            providers: [TwoFaProviderInfo(type: 'TOTP', isDefault: true)],
          ),
        );
        const mfaConfig = AsyncData<AuthState>(
          AuthMfaConfigurationRequired(preAuthToken: 'cfg-token'),
        );

        expect(
          tbAuthRedirect(auth: mfaVerify, uri: Uri.parse('/login')),
          AppRoutes.twoFactor,
        );
        expect(
          tbAuthRedirect(auth: mfaVerify, uri: Uri.parse('/login/2fa')),
          isNull,
        );
        expect(
          tbAuthRedirect(auth: mfaConfig, uri: Uri.parse('/login')),
          AppRoutes.mfaSetup,
        );
        expect(
          tbAuthRedirect(auth: mfaConfig, uri: Uri.parse('/login/2fa-setup')),
          isNull,
        );
      },
    );

    test(
      'authenticated state redirects away from auth routes and validates safe from param',
      () {
        const authed = AsyncData<AuthState>(
          AuthAuthenticated(
            session: TbAuthSession(
              accessToken: 'jwt',
              refreshToken: 'ref',
              userId: 'u-1',
              email: 'tenant@tb.io',
              authority: Authority.tenantAdmin,
            ),
            user: TbUserProfile(
              id: 'u-1',
              email: 'tenant@tb.io',
              authority: Authority.tenantAdmin,
            ),
            mode: SessionMode.live,
          ),
        );

        expect(
          tbAuthRedirect(auth: authed, uri: Uri.parse('/login')),
          AppRoutes.home,
        );
        expect(
          tbAuthRedirect(
            auth: authed,
            uri: Uri.parse('/login?from=%2Fcustomers'),
          ),
          '/customers',
        );
        expect(
          tbAuthRedirect(
            auth: authed,
            uri: Uri.parse('/login?from=https://evil.example.com'),
          ),
          AppRoutes.home,
        );
        expect(
          tbAuthRedirect(auth: authed, uri: Uri.parse('/devices')),
          isNull,
        );
      },
    );

    test(
      'normalizes custom-scheme OAuth callback query onto /oauth2/callback',
      () {
        const unauth = AsyncData<AuthState>(AuthUnauthenticated());
        final redirected = tbAuthRedirect(
          auth: unauth,
          uri: Uri.parse('/callback?accessToken=abc&refreshToken=def'),
        );
        expect(redirected, '/oauth2/callback?accessToken=abc&refreshToken=def');
      },
    );
  });

  group('GoRouter live widget redirect & shell integration', () {
    testWidgets(
      'boots to /login when unauthenticated and navigates to /home on Demo login',
      (WidgetTester tester) async {
        await tester.pumpWidget(
          ProviderScope(
            overrides: buildOverrides(),
            child: const ThingsboardDemoCloudApp(),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Login to your account'), findsOneWidget);
        expect(find.byKey(const Key('try-demo-mode-button')), findsOneWidget);

        await tester.tap(find.byKey(const Key('try-demo-mode-button')));
        await tester.pumpAndSettle();

        expect(find.text('DEMO'), findsOneWidget);
        expect(find.text('Home'), findsWidgets);
      },
    );

    testWidgets(
      'cold-start OAuth2 callback persists tokens and redirects to /home',
      (WidgetTester tester) async {
        adapter.on(
          'GET',
          '/api/v2/alarms',
          (_) => MockDioAdapter.jsonResponse({
            'data': <Object>[],
            'totalPages': 0,
            'totalElements': 0,
            'hasNext': false,
          }),
        );
        adapter.on(
          'GET',
          '/api/notifications/unread/count',
          (_) => MockDioAdapter.jsonResponse({'totalUnreadCount': 0}),
        );

        final container = ProviderContainer(overrides: buildOverrides());

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: const ThingsboardDemoCloudApp(),
          ),
        );
        await tester.pumpAndSettle();

        final router = container.read(routerProvider);
        final jwt = _testJwt();
        router.go('/oauth2/callback?accessToken=$jwt&refreshToken=oauth-ref');
        await tester.pumpAndSettle();

        expect(
          container.read(authProvider).valueOrNull,
          isA<AuthAuthenticated>(),
        );
        expect(router.routeInformationProvider.value.uri.path, AppRoutes.home);

        await tester.pumpWidget(const SizedBox.shrink());
        container.dispose();
        await tester.pump();
      },
    );
  });
}
