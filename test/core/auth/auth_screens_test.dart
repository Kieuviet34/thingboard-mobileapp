import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:thingsboard_democloud_app/config/themes/tb_theme.dart';
import 'package:thingsboard_democloud_app/core/api/controllers/auth_controller.dart';
import 'package:thingsboard_democloud_app/core/api/controllers/server_config_controller.dart';
import 'package:thingsboard_democloud_app/core/auth/oauth/oauth_callback_page.dart';
import 'package:thingsboard_democloud_app/core/auth/reset_password/reset_password_request_page.dart';
import 'package:thingsboard_democloud_app/core/auth/two_factor/mfa_setup_page.dart';
import 'package:thingsboard_democloud_app/core/auth/two_factor/two_factor_auth_page.dart';
import 'package:thingsboard_democloud_app/core/models/models.dart';
import 'package:thingsboard_democloud_app/main.dart';
import 'package:thingsboard_democloud_app/utils/ui/qr_code_scanner/qr_code_scanner_page.dart';

import '../../helpers/fake_app_preferences.dart';
import '../../helpers/fake_secure_storage.dart';
import '../../helpers/fake_ws_channel.dart';
import '../../helpers/mock_dio_adapter.dart';

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
      (_) => MockDioAdapter.jsonResponse([
        {
          'name': 'Google',
          'icon': 'google-logo',
          'url': '/oauth2/authorization/google',
        },
      ]),
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
  });

  List<Override> buildOverrides() => [
    tbStorageProvider.overrideWithValue(storage),
    tbAppPreferencesProvider.overrideWithValue(prefs),
    tbHttpClientAdapterProvider.overrideWithValue(adapter),
    wsChannelFactoryProvider.overrideWithValue((_) => FakeWebSocketChannel()),
  ];

  group('Auth screens (Login, Server URL, Reset, 2FA, MFA Setup, OAuth, QR)', () {
    testWidgets(
      'LoginPage shows inline TbFailure error banner on 401 and preserves email',
      (WidgetTester tester) async {
        adapter.on(
          'POST',
          '/api/auth/login',
          (_) => MockDioAdapter.jsonResponse({
            'status': 401,
            'errorCode': 10,
            'message': 'Invalid username or password',
          }, statusCode: 401),
        );

        await tester.pumpWidget(
          ProviderScope(
            overrides: buildOverrides(),
            child: const ThingsboardDemoCloudApp(),
          ),
        );
        await tester.pumpAndSettle();

        await tester.enterText(
          find.byType(TextField).first,
          'tenant@thingsboard.org',
        );
        await tester.enterText(find.byType(TextField).last, 'wrong-pass');
        await tester.pump();
        await tester.tap(find.byKey(const Key('login-submit-button')));
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('login-error-banner')), findsOneWidget);
        expect(find.text('Invalid username or password'), findsOneWidget);
        expect(find.text('tenant@thingsboard.org'), findsOneWidget);
      },
    );

    testWidgets(
      'LoginPage switches Server URL via modal sheet and survives 2.0x text scale',
      (WidgetTester tester) async {
        final container = ProviderContainer(overrides: buildOverrides());

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: const MediaQuery(
              data: MediaQueryData(textScaler: TextScaler.linear(2.0)),
              child: ThingsboardDemoCloudApp(),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('server-url-pill')), findsOneWidget);
        await tester.tap(find.byKey(const Key('server-url-pill')));
        await tester.pumpAndSettle();

        await tester.enterText(
          find.byKey(const Key('server-url-input')),
          'https://tb.custom.example.com',
        );
        await tester.tap(find.byKey(const Key('save-server-url-button')));
        await tester.pumpAndSettle();

        expect(
          container.read(serverConfigProvider).baseUrl,
          'https://tb.custom.example.com/',
        );
        expect(find.text('tb.custom.example.com'), findsOneWidget);
        expect(tester.takeException(), isNull);

        await tester.pumpWidget(const SizedBox.shrink());
        container.dispose();
        await tester.pump();
      },
    );

    testWidgets(
      'LoginPage routes PRE_VERIFICATION_TOKEN to TwoFactorAuthPage and completes OTP',
      (WidgetTester tester) async {
        adapter.on(
          'POST',
          '/api/auth/login',
          (_) => MockDioAdapter.jsonResponse({
            'token': 'pre-verify-jwt',
            'scope': 'PRE_VERIFICATION_TOKEN',
          }),
        );
        adapter.on(
          'GET',
          '/api/auth/2fa/providers',
          (_) => MockDioAdapter.jsonResponse([
            {'type': 'TOTP', 'default': true},
            {'type': 'EMAIL', 'default': false, 'contact': 't***@tb.io'},
          ]),
        );
        adapter.on(
          'POST',
          '/api/auth/2fa/verification/check',
          (_) => MockDioAdapter.jsonResponse({
            'token': _testJwt(),
            'refreshToken': 'ref-2fa',
          }),
        );

        final container = ProviderContainer(overrides: buildOverrides());

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: const ThingsboardDemoCloudApp(),
          ),
        );
        await tester.pumpAndSettle();

        await tester.enterText(find.byType(TextField).first, 'tenant@tb.io');
        await tester.enterText(find.byType(TextField).last, 'secret');
        await tester.pump();
        await tester.tap(find.byKey(const Key('login-submit-button')));
        await tester.pumpAndSettle();

        expect(find.byType(TwoFactorAuthPage), findsOneWidget);
        expect(find.text('Enter verification code'), findsOneWidget);

        await tester.enterText(
          find.byKey(const Key('two-fa-code-input')),
          '123456',
        );
        await tester.tap(find.byKey(const Key('two-fa-verify-button')));
        await tester.pumpAndSettle();

        expect(
          container.read(authProvider).valueOrNull,
          isA<AuthAuthenticated>(),
        );

        await tester.pumpWidget(const SizedBox.shrink());
        container.dispose();
        await tester.pump();
      },
    );

    testWidgets(
      'MfaSetupPage handles MFA_CONFIGURATION_TOKEN continue and cancel',
      (WidgetTester tester) async {
        adapter.on(
          'POST',
          '/api/auth/login',
          (_) => MockDioAdapter.jsonResponse({
            'token': 'mfa-config-jwt',
            'scope': 'MFA_CONFIGURATION_TOKEN',
          }),
        );

        final container = ProviderContainer(overrides: buildOverrides());

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: const ThingsboardDemoCloudApp(),
          ),
        );
        await tester.pumpAndSettle();

        await tester.enterText(find.byType(TextField).first, 'tenant@tb.io');
        await tester.enterText(find.byType(TextField).last, 'secret');
        await tester.pump();
        await tester.tap(find.byKey(const Key('login-submit-button')));
        await tester.pumpAndSettle();

        expect(find.byType(MfaSetupPage), findsOneWidget);
        expect(find.text('2FA setup required'), findsOneWidget);

        await tester.tap(find.byKey(const Key('mfa-setup-cancel-button')));
        await tester.pumpAndSettle();

        expect(
          container.read(authProvider).valueOrNull,
          isA<AuthUnauthenticated>(),
        );
        expect(find.text('Login to your account'), findsOneWidget);

        await tester.pumpWidget(const SizedBox.shrink());
        container.dispose();
        await tester.pump();
      },
    );

    testWidgets(
      'ResetPasswordRequestPage submits email and displays confirmation',
      (WidgetTester tester) async {
        var resetCalled = false;
        adapter.on('POST', '/api/noauth/resetPasswordByEmail', (_) {
          resetCalled = true;
          return MockDioAdapter.jsonResponse({});
        });

        await tester.pumpWidget(
          ProviderScope(
            overrides: buildOverrides(),
            child: MaterialApp(
              theme: tbLightTheme(),
              home: const ResetPasswordRequestPage(),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.enterText(find.byType(TextField), 'user@thingsboard.org');
        await tester.pump();
        await tester.tap(find.byKey(const Key('request-reset-submit-button')));
        await tester.pumpAndSettle();

        expect(resetCalled, isTrue);
        expect(
          find.byKey(const Key('reset-password-sent-banner')),
          findsOneWidget,
        );
      },
    );

    testWidgets('OAuthCallbackPage shows error state when token is missing', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: buildOverrides(),
          child: MaterialApp(
            theme: tbDarkTheme(),
            home: const OAuthCallbackPage(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Sign-in failed'), findsOneWidget);
      expect(find.text('Back to login'), findsOneWidget);
    });

    testWidgets(
      'QrCodeScannerPage simulates QR login and device claim with reduced motion',
      (WidgetTester tester) async {
        adapter.on(
          'GET',
          '/api/noauth/qr/demo-qr-login-secret',
          (_) => MockDioAdapter.jsonResponse({
            'token': _testJwt(),
            'refreshToken': 'qr-ref',
          }),
        );
        adapter.on(
          'POST',
          '/api/customer/device/SN-001/claim',
          (_) => MockDioAdapter.jsonResponse({'response': 'CLAIMED'}),
        );

        final container = ProviderContainer(overrides: buildOverrides());

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MediaQuery(
              data: const MediaQueryData(disableAnimations: true),
              child: MaterialApp(
                theme: tbLightTheme(),
                home: const QrCodeScannerPage(enableCamera: false),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('qr-simulate-claim-button')));
        await tester.pumpAndSettle();
        expect(find.textContaining('CLAIMED'), findsOneWidget);

        await tester.tap(find.byKey(const Key('qr-simulate-login-button')));
        await tester.pumpAndSettle();
        expect(
          container.read(authProvider).valueOrNull,
          isA<AuthAuthenticated>(),
        );

        await tester.pumpWidget(const SizedBox.shrink());
        container.dispose();
        await tester.pump();
      },
    );
  });
}
