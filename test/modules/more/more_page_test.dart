import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:thingsboard_democloud_app/config/themes/design_tokens.dart';
import 'package:thingsboard_democloud_app/config/themes/tb_theme.dart';
import 'package:thingsboard_democloud_app/core/api/controllers/auth_controller.dart';
import 'package:thingsboard_democloud_app/core/api/controllers/notification_controller.dart';
import 'package:thingsboard_democloud_app/core/api/controllers/server_config_controller.dart';
import 'package:thingsboard_democloud_app/core/models/auth_models.dart';
import 'package:thingsboard_democloud_app/core/models/entity_id.dart';
import 'package:thingsboard_democloud_app/core/models/user_models.dart';
import 'package:thingsboard_democloud_app/modules/more/more_page.dart';
import 'package:thingsboard_democloud_app/widgets/icons/tb_icons.dart';

import '../../helpers/fake_app_preferences.dart';
import '../../helpers/fake_secure_storage.dart';
import '../../helpers/fake_ws_channel.dart';
import '../../helpers/mock_dio_adapter.dart';

class _StubAuthController extends AuthController {
  _StubAuthController(this._initial);

  final AuthState _initial;
  int logoutCalls = 0;

  @override
  Future<AuthState> build() async => _initial;

  @override
  Future<void> logout() async {
    logoutCalls++;
    state = const AsyncData<AuthState>(AuthUnauthenticated());
  }
}

AuthAuthenticated _buildAuth({
  required Authority authority,
  required SessionMode mode,
}) {
  return AuthAuthenticated(
    session: TbAuthSession(
      accessToken: 'jwt',
      refreshToken: 'refresh',
      userId: 'u-1',
      email: 'ops@tb.io',
      authority: authority,
    ),
    user: TbUserProfile(
      id: 'u-1',
      email: 'ops@tb.io',
      authority: authority,
      firstName: 'Alex',
      lastName: 'Chen',
    ),
    mode: mode,
  );
}

void main() {
  Widget buildApp({
    required _StubAuthController authController,
    int unreadCount = 3,
    ThemeData? theme,
    double textScale = 1.0,
    bool disableAnimations = false,
  }) {
    return ProviderScope(
      overrides: [
        tbStorageProvider.overrideWithValue(FakeSecureStorage()),
        tbAppPreferencesProvider.overrideWithValue(FakeAppPreferences()),
        tbHttpClientAdapterProvider.overrideWithValue(MockDioAdapter()),
        wsChannelFactoryProvider.overrideWithValue(
          (_) => FakeWebSocketChannel(),
        ),
        authProvider.overrideWith(() => authController),
        unreadNotificationsCountProvider.overrideWith(
          (ref) => Stream<int>.value(unreadCount),
        ),
      ],
      child: MediaQuery(
        data: MediaQueryData(
          size: const Size(390, 844),
          textScaler: TextScaler.linear(textScale),
          disableAnimations: disableAnimations,
        ),
        child: MaterialApp(
          theme: theme ?? tbLightTheme(),
          home: const MorePage(),
        ),
      ),
    );
  }

  group('MorePage', () {
    testWidgets(
      'Tenant Admin sees Customers, Assets, Audit Logs, Notifications badge, and Demo badge',
      (tester) async {
        final auth = _StubAuthController(
          _buildAuth(authority: Authority.tenantAdmin, mode: SessionMode.demo),
        );
        await tester.pumpWidget(buildApp(authController: auth, unreadCount: 5));
        await tester.pumpAndSettle();

        expect(find.text('Alex Chen'), findsOneWidget);
        expect(find.text('DEMO'), findsOneWidget);
        expect(find.text('Customers'), findsOneWidget);
        expect(find.text('Assets'), findsOneWidget);
        expect(find.text('Audit Logs'), findsOneWidget);
        expect(find.text('Notifications'), findsOneWidget);
        expect(find.text('5'), findsOneWidget);
        expect(find.text('Profile & Settings'), findsOneWidget);
        expect(find.byType(TbIcon), findsWidgets);

        final logoutRect = tester.getRect(
          find.byKey(const Key('more_logout_button')),
        );
        expect(
          logoutRect.height,
          greaterThanOrEqualTo(DesignTokens.minTouchTarget),
        );
      },
    );

    testWidgets('CUSTOMER_USER hides Customers entry', (tester) async {
      final auth = _StubAuthController(
        _buildAuth(authority: Authority.customerUser, mode: SessionMode.live),
      );
      await tester.pumpWidget(buildApp(authController: auth, unreadCount: 0));
      await tester.pumpAndSettle();

      expect(find.text('LIVE'), findsOneWidget);
      expect(find.text('Customers'), findsNothing);
      expect(find.text('Assets'), findsOneWidget);
      expect(find.text('Audit Logs'), findsOneWidget);
    });

    testWidgets('logout button opens confirmation dialog and invokes logout', (
      tester,
    ) async {
      final auth = _StubAuthController(
        _buildAuth(authority: Authority.tenantAdmin, mode: SessionMode.demo),
      );
      await tester.pumpWidget(
        buildApp(authController: auth, disableAnimations: true),
      );
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.byKey(const Key('more_logout_button')),
        200,
      );
      await tester.tap(find.byKey(const Key('more_logout_button')));
      await tester.pumpAndSettle();

      expect(find.text('Log out?'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Log out'));
      await tester.pumpAndSettle();

      expect(auth.logoutCalls, 1);
    });

    testWidgets('renders cleanly in Dark theme at 2.0x text scale', (
      tester,
    ) async {
      final auth = _StubAuthController(
        _buildAuth(authority: Authority.tenantAdmin, mode: SessionMode.demo),
      );
      await tester.pumpWidget(
        buildApp(
          authController: auth,
          theme: tbDarkTheme(),
          textScale: 2.0,
          disableAnimations: true,
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('More'), findsOneWidget);
      expect(find.text('Customers'), findsOneWidget);
    });
  });
}
