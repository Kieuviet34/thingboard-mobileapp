import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:thingsboard_democloud_app/config/themes/tb_theme.dart';
import 'package:thingsboard_democloud_app/core/api/controllers/auth_controller.dart';
import 'package:thingsboard_democloud_app/core/api/controllers/server_config_controller.dart';
import 'package:thingsboard_democloud_app/core/auth/two_factor/two_factor_auth_page.dart';
import 'package:thingsboard_democloud_app/core/models/auth_models.dart';

import '../../helpers/fake_app_preferences.dart';
import '../../helpers/fake_secure_storage.dart';
import '../../helpers/fake_ws_channel.dart';
import '../../helpers/mock_dio_adapter.dart';
import '../../helpers/test_container.dart';

const _preAuthToken = 'pre-verify-jwt-1';
const _checkPath = '/api/auth/2fa/verification/check';
const _sendPath = '/api/auth/2fa/verification/send';

const _totpChipKey = Key('two-fa-provider-TOTP');
const _emailChipKey = Key('two-fa-provider-EMAIL');
const _codeFieldKey = Key('two-fa-code-input');
const _verifyKey = Key('two-fa-verify-button');
const _resendKey = Key('two-fa-resend-button');
const _errorBannerKey = Key('two-fa-error-banner');

const _twoProviders = <TwoFaProviderInfo>[
  TwoFaProviderInfo(type: 'TOTP', isDefault: true),
  TwoFaProviderInfo(type: 'EMAIL', contact: 'user@example.com'),
];

/// Replaces the auth controller's initial state so the page can be driven
/// directly. Inherited methods (verifyTwoFa, sendTwoFaCode, cancelMfa, ...)
/// still run the real code against [MockDioAdapter].
class _SeededAuthController extends AuthController {
  _SeededAuthController(this._seed);

  final AuthState _seed;

  @override
  Future<AuthState> build() async => _seed;
}

AuthMfaVerificationRequired _mfaState({
  List<TwoFaProviderInfo> providers = _twoProviders,
}) {
  return AuthMfaVerificationRequired(
    preAuthToken: _preAuthToken,
    providers: providers,
  );
}

List<RequestOptions> _requestsTo(MockDioAdapter adapter, String path) {
  return adapter.capturedRequests.where((r) => r.path == path).toList();
}

void main() {
  late MockDioAdapter adapter;
  late FakeSecureStorage storage;

  setUp(() {
    adapter = MockDioAdapter();
    storage = FakeSecureStorage();
    adapter
      ..on(
        'GET',
        '/api/auth/user',
        (_) => MockDioAdapter.jsonResponse({
          'id': {'entityType': 'USER', 'id': 'u-1'},
          'email': 'user@example.com',
          'authority': 'TENANT_ADMIN',
        }),
      )
      ..on(
        'GET',
        '/api/system/info',
        (_) => MockDioAdapter.jsonResponse({'version': '4.4.1PE'}),
      )
      ..on(
        'POST',
        _checkPath,
        (_) => MockDioAdapter.jsonResponse({
          'token': 'jwt-1',
          'refreshToken': 'refresh-1',
        }),
      )
      ..on('POST', _sendPath, (_) => MockDioAdapter.emptyResponse());
  });

  Future<ProviderContainer> pumpPage(
    WidgetTester tester, {
    AuthState? seed,
    ThemeData? theme,
    double textScale = 1,
  }) async {
    tester.view
      ..physicalSize = const Size(360, 740)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final container = createTestContainer(
      overrides: [
        tbStorageProvider.overrideWithValue(storage),
        tbAppPreferencesProvider.overrideWithValue(FakeAppPreferences()),
        tbHttpClientAdapterProvider.overrideWithValue(adapter),
        wsChannelFactoryProvider.overrideWithValue(
          (_) => FakeWebSocketChannel(),
        ),
        authProvider.overrideWith(
          () => _SeededAuthController(seed ?? _mfaState()),
        ),
      ],
    );
    // The real router resolves auth state before this screen is shown. Do the
    // same here so taps never race the lazy AsyncNotifier build.
    await container.read(authProvider.future);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MediaQuery(
          data: MediaQueryData.fromView(
            tester.view,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: MaterialApp(
            theme: theme ?? tbLightTheme(),
            home: const TwoFactorAuthPage(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  /// Lets in-flight Dio requests complete without `pumpAndSettle`, which would
  /// never return while the loading progress indicator is animating.
  Future<void> pumpFrames(WidgetTester tester) async {
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> enterCode(WidgetTester tester, String code) async {
    await tester.enterText(find.byKey(_codeFieldKey), code);
    await tester.pump();
  }

  Future<void> tapVerify(WidgetTester tester) async {
    await tester.tap(find.byKey(_verifyKey));
    await pumpFrames(tester);
  }

  group('provider list', () {
    testWidgets(
      'renders the code field, one chip per provider and the default TOTP provider',
      (tester) async {
        await pumpPage(tester);

        expect(find.text('Enter verification code'), findsOneWidget);
        expect(find.byKey(_totpChipKey), findsOneWidget);
        expect(find.byKey(_emailChipKey), findsOneWidget);
        expect(
          tester.widget<ChoiceChip>(find.byKey(_totpChipKey)).selected,
          isTrue,
        );
        expect(
          tester.widget<ChoiceChip>(find.byKey(_emailChipKey)).selected,
          isFalse,
        );
        expect(find.text('TOTP code'), findsOneWidget);
        expect(find.byKey(_verifyKey), findsOneWidget);
        // TOTP codes come from an authenticator app, so there is nothing to resend.
        expect(find.byKey(_resendKey), findsNothing);
      },
    );

    testWidgets('shows no provider chips when only one provider is available', (
      tester,
    ) async {
      await pumpPage(
        tester,
        seed: _mfaState(
          providers: const [TwoFaProviderInfo(type: 'TOTP', isDefault: true)],
        ),
      );

      expect(find.byType(ChoiceChip), findsNothing);
      expect(find.text('TOTP code'), findsOneWidget);
    });

    testWidgets('falls back to a TOTP-only form when no MFA state is present', (
      tester,
    ) async {
      await pumpPage(tester, seed: const AuthUnauthenticated());

      expect(find.byType(ChoiceChip), findsNothing);
      expect(find.text('TOTP code'), findsOneWidget);
    });
  });

  group('provider selection', () {
    testWidgets('selecting EMAIL switches the code label and offers resend', (
      tester,
    ) async {
      await pumpPage(tester);

      await tester.tap(find.byKey(_emailChipKey));
      await tester.pumpAndSettle();

      expect(
        tester.widget<ChoiceChip>(find.byKey(_emailChipKey)).selected,
        isTrue,
      );
      expect(
        tester.widget<ChoiceChip>(find.byKey(_totpChipKey)).selected,
        isFalse,
      );
      expect(find.text('EMAIL code'), findsOneWidget);
      expect(find.text('Resend code'), findsOneWidget);
    });

    testWidgets('selecting a provider clears a previous error banner', (
      tester,
    ) async {
      await pumpPage(tester);
      await tapVerify(tester);
      expect(find.byKey(_errorBannerKey), findsOneWidget);

      await tester.tap(find.byKey(_emailChipKey));
      await tester.pumpAndSettle();

      expect(find.byKey(_errorBannerKey), findsNothing);
    });
  });

  group('verifying a code', () {
    testWidgets(
      'blank or short code shows the 6-digit prompt and sends no check request',
      (tester) async {
        await pumpPage(tester);

        await tapVerify(tester);
        expect(find.byKey(_errorBannerKey), findsOneWidget);
        expect(
          find.text('Enter the 6-digit verification code'),
          findsOneWidget,
        );

        await enterCode(tester, '12345');
        await tapVerify(tester);
        expect(
          find.text('Enter the 6-digit verification code'),
          findsOneWidget,
        );

        expect(_requestsTo(adapter, _checkPath), isEmpty);
      },
    );

    testWidgets(
      'valid code posts providerType and code with the pre-auth token and authenticates',
      (tester) async {
        final container = await pumpPage(tester);

        await enterCode(tester, '123456');
        await tapVerify(tester);

        final requests = _requestsTo(adapter, _checkPath);
        expect(requests, hasLength(1));
        expect(requests.single.method, 'POST');
        expect(requests.single.queryParameters, {
          'providerType': 'TOTP',
          'verificationCode': '123456',
        });
        expect(
          requests.single.headers['X-Authorization'],
          'Bearer $_preAuthToken',
        );

        expect(
          container.read(authProvider).valueOrNull,
          isA<AuthAuthenticated>().having(
            (s) => s.session.accessToken,
            'session.accessToken',
            'jwt-1',
          ),
        );
        expect(find.byKey(_errorBannerKey), findsNothing);
      },
    );

    testWidgets('keyboard submit verifies the code with the active provider', (
      tester,
    ) async {
      final container = await pumpPage(tester);

      await tester.tap(find.byKey(_codeFieldKey));
      await enterCode(tester, '654321');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await pumpFrames(tester);

      expect(_requestsTo(adapter, _checkPath), hasLength(1));
      expect(
        container.read(authProvider).valueOrNull,
        isA<AuthAuthenticated>(),
      );
    });

    testWidgets(
      'server error shows the server message, keeps the typed code and re-enables Verify',
      (tester) async {
        adapter.on(
          'POST',
          _checkPath,
          (_) => MockDioAdapter.jsonResponse({
            'status': 400,
            'message': 'Verification code is incorrect',
            'errorCode': 31,
          }, statusCode: 400),
        );
        final container = await pumpPage(tester);

        await enterCode(tester, '123456');
        await tapVerify(tester);

        expect(find.byKey(_errorBannerKey), findsOneWidget);
        expect(find.text('Verification code is incorrect'), findsOneWidget);
        expect(
          tester.widget<TextField>(find.byKey(_codeFieldKey)).controller!.text,
          '123456',
        );
        expect(
          tester.widget<FilledButton>(find.byKey(_verifyKey)).onPressed,
          isNotNull,
        );
        expect(
          container.read(authProvider).valueOrNull,
          isA<AuthMfaVerificationRequired>(),
        );
      },
    );

    testWidgets(
      'after a 401 the user can retry and succeed without reopening the screen',
      (tester) async {
        adapter.enqueue(
          'POST',
          _checkPath,
          (_) => MockDioAdapter.jsonResponse({
            'status': 401,
            'message': 'Invalid verification code',
          }, statusCode: 401),
        );
        final container = await pumpPage(tester);

        await enterCode(tester, '111111');
        await tapVerify(tester);
        expect(find.text('Invalid verification code'), findsOneWidget);
        expect(
          container.read(authProvider).valueOrNull,
          isA<AuthMfaVerificationRequired>(),
        );

        await enterCode(tester, '222222');
        await tapVerify(tester);
        expect(find.byKey(_errorBannerKey), findsNothing);
        expect(
          container.read(authProvider).valueOrNull,
          isA<AuthAuthenticated>(),
        );
        expect(_requestsTo(adapter, _checkPath), hasLength(2));
      },
    );

    testWidgets(
      'while verifying the button is disabled, a repeat tap sends nothing, and the progress bar shows',
      (tester) async {
        final gate = Completer<void>();
        adapter.on('POST', _checkPath, (_) async {
          await gate.future;
          return MockDioAdapter.jsonResponse({'token': 'jwt-1'});
        });
        await pumpPage(tester);

        await enterCode(tester, '123456');
        await tester.tap(find.byKey(_verifyKey));
        await pumpFrames(tester);

        expect(
          tester.widget<FilledButton>(find.byKey(_verifyKey)).onPressed,
          isNull,
        );
        expect(find.byType(LinearProgressIndicator), findsOneWidget);
        expect(_requestsTo(adapter, _checkPath), hasLength(1));

        await tester.tap(find.byKey(_verifyKey));
        await pumpFrames(tester);
        expect(_requestsTo(adapter, _checkPath), hasLength(1));

        gate.complete();
        await tester.pumpAndSettle();

        expect(find.byType(LinearProgressIndicator), findsNothing);
        expect(
          tester.widget<FilledButton>(find.byKey(_verifyKey)).onPressed,
          isNotNull,
        );
      },
    );
  });

  group('resend code', () {
    testWidgets(
      'sends the code to the selected provider, then cools down before allowing resend',
      (tester) async {
        await pumpPage(tester);
        await tester.tap(find.byKey(_emailChipKey));
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(_resendKey));
        await pumpFrames(tester);

        final requests = _requestsTo(adapter, _sendPath);
        expect(requests, hasLength(1));
        expect(requests.single.queryParameters, {'providerType': 'EMAIL'});
        expect(
          requests.single.headers['X-Authorization'],
          'Bearer $_preAuthToken',
        );
        expect(find.text('Resend code (30s)'), findsOneWidget);
        expect(
          tester.widget<TextButton>(find.byKey(_resendKey)).onPressed,
          isNull,
        );

        // A tap during cooldown must not send another code.
        await tester.tap(find.byKey(_resendKey));
        await pumpFrames(tester);
        expect(_requestsTo(adapter, _sendPath), hasLength(1));

        await tester.pump(const Duration(seconds: 30));
        expect(find.text('Resend code'), findsOneWidget);
        expect(
          tester.widget<TextButton>(find.byKey(_resendKey)).onPressed,
          isNotNull,
        );
      },
    );

    testWidgets('a failed resend shows the server message', (tester) async {
      adapter.on(
        'POST',
        _sendPath,
        (_) => MockDioAdapter.jsonResponse({
          'status': 400,
          'message': 'Email provider is not configured',
          'errorCode': 31,
        }, statusCode: 400),
      );
      await pumpPage(tester);
      await tester.tap(find.byKey(_emailChipKey));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(_resendKey));
      await pumpFrames(tester);

      expect(find.byKey(_errorBannerKey), findsOneWidget);
      expect(find.text('Email provider is not configured'), findsOneWidget);
    });
  });

  group('back to login', () {
    testWidgets(
      'back arrow cancels MFA, returns to unauthenticated and never verifies',
      (tester) async {
        final container = await pumpPage(tester);

        await tester.tap(find.byTooltip('Back to login'));
        await tester.pumpAndSettle();

        expect(
          container.read(authProvider).valueOrNull,
          isA<AuthUnauthenticated>(),
        );
        expect(_requestsTo(adapter, _checkPath), isEmpty);
      },
    );

    testWidgets('system back gesture cancels MFA the same way', (tester) async {
      final container = await pumpPage(tester);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(
        container.read(authProvider).valueOrNull,
        isA<AuthUnauthenticated>(),
      );
      expect(_requestsTo(adapter, _checkPath), isEmpty);
    });
  });

  group('accessibility and layout', () {
    testWidgets('meets Android tap-target and labelled tap-target guidelines', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await pumpPage(tester);

      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));

      await tapVerify(tester);
      expect(find.byKey(_errorBannerKey), findsOneWidget);
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));

      semantics.dispose();
    });

    testWidgets(
      'survives 2.0x text scale with a long server error without overflow',
      (tester) async {
        adapter.on(
          'POST',
          _checkPath,
          (_) => MockDioAdapter.jsonResponse({
            'status': 400,
            'message':
                'The verification code you entered is not valid for this account. Request a new code and try again.',
            'errorCode': 31,
          }, statusCode: 400),
        );
        await pumpPage(tester, textScale: 2);

        await enterCode(tester, '123456');
        await tapVerify(tester);

        expect(tester.takeException(), isNull);
        expect(find.byKey(_errorBannerKey), findsOneWidget);
        expect(find.byKey(_verifyKey), findsOneWidget);
      },
    );

    for (final themeName in ['light', 'dark']) {
      testWidgets('renders the error banner in the $themeName theme', (
        tester,
      ) async {
        final theme = themeName == 'light' ? tbLightTheme() : tbDarkTheme();
        await pumpPage(tester, theme: theme);

        await tapVerify(tester);

        expect(tester.takeException(), isNull);
        final banner = tester.widget<Container>(find.byKey(_errorBannerKey));
        expect(
          (banner.decoration! as BoxDecoration).color,
          theme.colorScheme.errorContainer,
        );
      });
    }
  });
}
