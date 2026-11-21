import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:thingsboard_democloud_app/config/themes/tb_theme.dart';
import 'package:thingsboard_democloud_app/core/api/controllers/auth_controller.dart';
import 'package:thingsboard_democloud_app/core/api/controllers/server_config_controller.dart';
import 'package:thingsboard_democloud_app/core/auth/two_factor/mfa_setup_page.dart';
import 'package:thingsboard_democloud_app/core/models/auth_models.dart';

import '../../helpers/fake_app_preferences.dart';
import '../../helpers/fake_secure_storage.dart';
import '../../helpers/fake_ws_channel.dart';
import '../../helpers/mock_dio_adapter.dart';
import '../../helpers/test_container.dart';

const _configTokenPath = '/api/auth/2fa/login';
const _preAuthToken = 'mfa-config-jwt-1';

const _continueKey = Key('mfa-setup-continue-button');
const _cancelKey = Key('mfa-setup-cancel-button');
const _errorBannerKey = Key('mfa-setup-error-banner');

/// Replaces the auth controller's initial state so the page can be driven
/// directly. Inherited methods (completeMfaConfiguration, cancelMfa) still run
/// the real code against [MockDioAdapter].
class _SeededAuthController extends AuthController {
  _SeededAuthController(this._seed);

  final AuthState _seed;

  @override
  Future<AuthState> build() async => _seed;
}

const _mfaConfigState = AuthMfaConfigurationRequired(
  preAuthToken: _preAuthToken,
);

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
        'POST',
        _configTokenPath,
        (_) => MockDioAdapter.jsonResponse({
          'token': 'jwt-1',
          'refreshToken': 'refresh-1',
        }),
      )
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
      );
  });

  Future<ProviderContainer> pumpPage(
    WidgetTester tester, {
    AuthState seed = _mfaConfigState,
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
        authProvider.overrideWith(() => _SeededAuthController(seed)),
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
            home: const MfaSetupPage(),
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

  Future<void> tapContinue(WidgetTester tester) async {
    await tester.tap(find.byKey(_continueKey));
    await pumpFrames(tester);
  }

  group('rendering', () {
    testWidgets(
      'shows the required-setup copy and both actions without an error banner',
      (tester) async {
        await pumpPage(tester);

        expect(find.text('2FA setup required'), findsOneWidget);
        expect(
          find.text('Configure two-factor authentication for your account'),
          findsOneWidget,
        );
        expect(find.byKey(_continueKey), findsOneWidget);
        expect(find.byKey(_cancelKey), findsOneWidget);
        expect(find.text('Continue'), findsOneWidget);
        expect(find.byKey(_errorBannerKey), findsNothing);
        expect(
          tester.widget<FilledButton>(find.byKey(_continueKey)).onPressed,
          isNotNull,
        );
      },
    );
  });

  group('continue', () {
    testWidgets(
      'exchanges the configuration token for a session and authenticates',
      (tester) async {
        final container = await pumpPage(tester);

        await tapContinue(tester);

        final requests = _requestsTo(adapter, _configTokenPath);
        expect(requests, hasLength(1));
        expect(requests.single.method, 'POST');
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

    testWidgets(
      'server error shows the message, stays on setup and re-enables Continue',
      (tester) async {
        adapter.enqueue(
          'POST',
          _configTokenPath,
          (_) => MockDioAdapter.jsonResponse({
            'status': 400,
            'message': 'Two-factor setup could not be completed',
            'errorCode': 31,
          }, statusCode: 400),
        );
        final container = await pumpPage(tester);

        await tapContinue(tester);

        expect(find.byKey(_errorBannerKey), findsOneWidget);
        expect(
          find.text('Two-factor setup could not be completed'),
          findsOneWidget,
        );
        expect(
          container.read(authProvider).valueOrNull,
          isA<AuthMfaConfigurationRequired>(),
        );
        expect(
          tester.widget<FilledButton>(find.byKey(_continueKey)).onPressed,
          isNotNull,
        );
      },
    );

    testWidgets(
      'after an error, Continue retries and clears the banner on success',
      (tester) async {
        adapter.enqueue(
          'POST',
          _configTokenPath,
          (_) => MockDioAdapter.jsonResponse({
            'status': 401,
            'message': 'Setup token expired',
          }, statusCode: 401),
        );
        final container = await pumpPage(tester);

        await tapContinue(tester);
        expect(find.text('Setup token expired'), findsOneWidget);

        await tapContinue(tester);

        expect(find.byKey(_errorBannerKey), findsNothing);
        expect(_requestsTo(adapter, _configTokenPath), hasLength(2));
        expect(
          container.read(authProvider).valueOrNull,
          isA<AuthAuthenticated>(),
        );
      },
    );

    testWidgets(
      'while submitting both actions are disabled, a repeat tap sends nothing, and the progress bar shows',
      (tester) async {
        final gate = Completer<void>();
        adapter.on('POST', _configTokenPath, (_) async {
          await gate.future;
          return MockDioAdapter.jsonResponse({'token': 'jwt-1'});
        });
        await pumpPage(tester);

        await tester.tap(find.byKey(_continueKey));
        await pumpFrames(tester);

        expect(
          tester.widget<FilledButton>(find.byKey(_continueKey)).onPressed,
          isNull,
        );
        expect(
          tester.widget<OutlinedButton>(find.byKey(_cancelKey)).onPressed,
          isNull,
        );
        expect(find.byType(LinearProgressIndicator), findsOneWidget);
        expect(_requestsTo(adapter, _configTokenPath), hasLength(1));

        await tester.tap(find.byKey(_continueKey));
        await pumpFrames(tester);
        expect(_requestsTo(adapter, _configTokenPath), hasLength(1));

        gate.complete();
        await tester.pumpAndSettle();

        expect(find.byType(LinearProgressIndicator), findsNothing);
      },
    );
  });

  group('back to login', () {
    testWidgets(
      'Back to login button cancels setup without calling the MFA endpoint',
      (tester) async {
        final container = await pumpPage(tester);

        await tester.tap(find.byKey(_cancelKey));
        await tester.pumpAndSettle();

        expect(
          container.read(authProvider).valueOrNull,
          isA<AuthUnauthenticated>(),
        );
        expect(_requestsTo(adapter, _configTokenPath), isEmpty);
      },
    );

    testWidgets('leading back arrow cancels setup the same way', (
      tester,
    ) async {
      final container = await pumpPage(tester);

      await tester.tap(find.byTooltip('Back to login'));
      await tester.pumpAndSettle();

      expect(
        container.read(authProvider).valueOrNull,
        isA<AuthUnauthenticated>(),
      );
      expect(_requestsTo(adapter, _configTokenPath), isEmpty);
    });

    testWidgets('system back gesture cancels setup the same way', (
      tester,
    ) async {
      final container = await pumpPage(tester);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(
        container.read(authProvider).valueOrNull,
        isA<AuthUnauthenticated>(),
      );
      expect(_requestsTo(adapter, _configTokenPath), isEmpty);
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

      adapter.enqueue(
        'POST',
        _configTokenPath,
        (_) => MockDioAdapter.jsonResponse({
          'status': 400,
          'message': 'Two-factor setup could not be completed',
          'errorCode': 31,
        }, statusCode: 400),
      );
      await tapContinue(tester);
      expect(find.byKey(_errorBannerKey), findsOneWidget);
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));

      semantics.dispose();
    });

    testWidgets(
      'survives 2.0x text scale with a long server error without overflow',
      (tester) async {
        adapter.enqueue(
          'POST',
          _configTokenPath,
          (_) => MockDioAdapter.jsonResponse({
            'status': 400,
            'message':
                'Two-factor setup could not be completed because the authenticator enrollment expired. Start the setup again from the login screen.',
            'errorCode': 31,
          }, statusCode: 400),
        );
        await pumpPage(tester, textScale: 2);

        await tapContinue(tester);

        expect(tester.takeException(), isNull);
        expect(find.byKey(_errorBannerKey), findsOneWidget);
        expect(find.byKey(_continueKey), findsOneWidget);
        expect(find.byKey(_cancelKey), findsOneWidget);
      },
    );

    for (final themeName in ['light', 'dark']) {
      testWidgets('renders the error banner in the $themeName theme', (
        tester,
      ) async {
        final theme = themeName == 'light' ? tbLightTheme() : tbDarkTheme();
        adapter.enqueue(
          'POST',
          _configTokenPath,
          (_) => MockDioAdapter.jsonResponse({
            'status': 400,
            'message': 'Two-factor setup could not be completed',
            'errorCode': 31,
          }, statusCode: 400),
        );
        await pumpPage(tester, theme: theme);

        await tapContinue(tester);

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
