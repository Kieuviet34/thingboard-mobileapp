import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:thingsboard_democloud_app/config/themes/design_tokens.dart';
import 'package:thingsboard_democloud_app/config/themes/tb_theme.dart';
import 'package:thingsboard_democloud_app/core/api/controllers/auth_controller.dart';
import 'package:thingsboard_democloud_app/core/api/controllers/notification_controller.dart';
import 'package:thingsboard_democloud_app/core/api/controllers/server_config_controller.dart';
import 'package:thingsboard_democloud_app/core/api/controllers/user_profile_controller.dart';
import 'package:thingsboard_democloud_app/core/api/repositories/notification_repository.dart';
import 'package:thingsboard_democloud_app/core/api/repositories/user_profile_repository.dart';
import 'package:thingsboard_democloud_app/core/models/auth_models.dart';
import 'package:thingsboard_democloud_app/core/models/entity_id.dart';
import 'package:thingsboard_democloud_app/core/models/notification_models.dart';
import 'package:thingsboard_democloud_app/core/models/pagination.dart';
import 'package:thingsboard_democloud_app/core/models/tb_failure.dart';
import 'package:thingsboard_democloud_app/core/models/user_models.dart';
import 'package:thingsboard_democloud_app/modules/profile/profile_settings_page.dart';
import 'package:thingsboard_democloud_app/widgets/tb_section_card.dart';
import 'package:thingsboard_democloud_app/widgets/tb_status_badge.dart';

import '../../helpers/fake_app_preferences.dart';
import '../../helpers/fake_secure_storage.dart';
import '../../helpers/fake_ws_channel.dart';
import '../../helpers/mock_dio_adapter.dart';

class _FakeUserProfileRepo implements UserProfileRepository {
  _FakeUserProfileRepo({TbUserProfile? user})
    : profile =
          user ??
          const TbUserProfile(
            id: 'u-1',
            email: 'admin@thingsboard.org',
            authority: Authority.tenantAdmin,
            firstName: 'Sarah',
            lastName: 'Connor',
            phone: '+1 555-8899',
          );

  TbUserProfile profile;
  int updateCalls = 0;
  int changePasswordCalls = 0;
  String? lastCurrentPassword;
  String? lastNewPassword;
  Object? changePasswordError;
  Completer<void>? changePasswordGate;

  @override
  Future<TbUserProfile> getUserProfile() async => profile;

  @override
  Future<TbUserProfile> updateUserProfile(TbUserProfile updated) async {
    updateCalls++;
    profile = updated;
    return profile;
  }

  @override
  Future<Map<String, dynamic>> getGeneralSettings() async => const {};

  @override
  Future<void> updateGeneralSettings(Map<String, dynamic> settings) async {}

  @override
  Future<LoginResponse> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    changePasswordCalls++;
    lastCurrentPassword = currentPassword;
    lastNewPassword = newPassword;
    await changePasswordGate?.future;
    if (changePasswordError != null) throw changePasswordError!;
    return const LoginResponse(token: 'new-jwt', refreshToken: 'new-refresh');
  }
}

class _FakeNotificationRepo implements NotificationRepository {
  TbUserNotificationSettings settings = const TbUserNotificationSettings(
    prefs: {
      'ALARM': {'WEB': true, 'MOBILE_APP': true, 'EMAIL': false},
    },
  );
  int saveSettingsCalls = 0;

  @override
  Future<PageData<TbNotification>> getNotifications(
    PageQuery query, {
    bool unreadOnly = false,
    dynamic cancelToken,
  }) async =>
      const PageData(data: [], totalPages: 1, totalElements: 0, hasNext: false);

  @override
  Future<int> getUnreadCount() async => 0;

  @override
  Future<void> markAsRead(String notificationId) async {}

  @override
  Future<void> markAllAsRead() async {}

  @override
  Future<void> deleteNotification(String notificationId) async {}

  @override
  Future<TbUserNotificationSettings> getNotificationSettings() async =>
      settings;

  @override
  Future<TbUserNotificationSettings> saveNotificationSettings(
    TbUserNotificationSettings updated,
  ) async {
    saveSettingsCalls++;
    settings = updated;
    return settings;
  }

  @override
  Future<void> registerMobileSession(String fcmToken) async {}

  @override
  Future<void> removeMobileSession(String fcmToken) async {}
}

class _StubAuthController extends AuthController {
  int logoutCalls = 0;

  @override
  Future<AuthState> build() async => const AuthUnauthenticated();

  @override
  Future<void> logout() async {
    logoutCalls++;
    state = const AsyncData<AuthState>(AuthUnauthenticated());
  }
}

class _PolicyServerConfig extends ServerConfigController {
  _PolicyServerConfig(this.policy);

  final UserPasswordPolicy? policy;

  @override
  ServerConfigState build() => super.build().copyWith(passwordPolicy: policy);
}

void main() {
  List<Override> baseOverrides({
    required _FakeUserProfileRepo userRepo,
    required _FakeNotificationRepo notifRepo,
    required _StubAuthController authCtrl,
    UserPasswordPolicy? policy,
  }) => [
    tbStorageProvider.overrideWithValue(FakeSecureStorage()),
    tbAppPreferencesProvider.overrideWithValue(FakeAppPreferences()),
    tbHttpClientAdapterProvider.overrideWithValue(MockDioAdapter()),
    wsChannelFactoryProvider.overrideWithValue((_) => FakeWebSocketChannel()),
    userProfileRepositoryProvider.overrideWithValue(userRepo),
    notificationRepositoryProvider.overrideWithValue(notifRepo),
    authProvider.overrideWith(() => authCtrl),
    if (policy != null)
      serverConfigProvider.overrideWith(() => _PolicyServerConfig(policy)),
  ];

  /// Mirrors NavigationPage: extendBody Scaffold + floating NavigationBar over
  /// a nested Navigator. Size and keyboard come from the test view.
  Widget buildShell({
    required _FakeUserProfileRepo userRepo,
    required _FakeNotificationRepo notifRepo,
    required _StubAuthController authCtrl,
    double textScale = 1.0,
  }) {
    return ProviderScope(
      overrides: baseOverrides(
        userRepo: userRepo,
        notifRepo: notifRepo,
        authCtrl: authCtrl,
      ),
      child: MaterialApp(
        theme: tbLightTheme(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: Scaffold(
          extendBody: true,
          bottomNavigationBar: NavigationBar(
            selectedIndex: 0,
            destinations: const [
              NavigationDestination(icon: Icon(Icons.home), label: 'A'),
              NavigationDestination(icon: Icon(Icons.list), label: 'B'),
              NavigationDestination(icon: Icon(Icons.map), label: 'C'),
              NavigationDestination(icon: Icon(Icons.person), label: 'D'),
            ],
          ),
          body: Navigator(
            onGenerateRoute: (_) => MaterialPageRoute<void>(
              builder: (_) => const ProfileSettingsPage(),
            ),
          ),
        ),
      ),
    );
  }

  Widget buildApp({
    required _FakeUserProfileRepo userRepo,
    required _FakeNotificationRepo notifRepo,
    required _StubAuthController authCtrl,
    ThemeData? theme,
    double textScale = 1.0,
    bool disableAnimations = false,
    UserPasswordPolicy? policy,
  }) {
    return ProviderScope(
      overrides: [
        tbStorageProvider.overrideWithValue(FakeSecureStorage()),
        tbAppPreferencesProvider.overrideWithValue(FakeAppPreferences()),
        tbHttpClientAdapterProvider.overrideWithValue(MockDioAdapter()),
        wsChannelFactoryProvider.overrideWithValue(
          (_) => FakeWebSocketChannel(),
        ),
        userProfileRepositoryProvider.overrideWithValue(userRepo),
        notificationRepositoryProvider.overrideWithValue(notifRepo),
        authProvider.overrideWith(() => authCtrl),
        if (policy != null)
          serverConfigProvider.overrideWith(() => _PolicyServerConfig(policy)),
      ],
      child: MediaQuery(
        data: MediaQueryData(
          size: const Size(390, 844),
          textScaler: TextScaler.linear(textScale),
          disableAnimations: disableAnimations,
        ),
        child: MaterialApp(
          theme: theme ?? tbLightTheme(),
          home: const ProfileSettingsPage(),
        ),
      ),
    );
  }

  group('ProfileSettingsPage', () {
    testWidgets(
      'renders user profile info, security, theme, and server tiles',
      (tester) async {
        final userRepo = _FakeUserProfileRepo();
        final notifRepo = _FakeNotificationRepo();
        final authCtrl = _StubAuthController();

        await tester.pumpWidget(
          buildApp(
            userRepo: userRepo,
            notifRepo: notifRepo,
            authCtrl: authCtrl,
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Profile & Settings'), findsOneWidget);
        expect(find.text('Sarah Connor'), findsOneWidget);
        expect(find.text('admin@thingsboard.org'), findsOneWidget);
        expect(find.text('Change Password'), findsOneWidget);
        expect(find.text('Theme Mode'), findsOneWidget);
        expect(find.text('ThingsBoard Server'), findsOneWidget);
        expect(find.text('Alarm Notification Channels'), findsOneWidget);

        final logoutRect = tester.getRect(
          find.byKey(const Key('profile_logout_button')),
        );
        expect(
          logoutRect.height,
          greaterThanOrEqualTo(DesignTokens.minTouchTarget),
        );
      },
    );

    testWidgets('Edit Profile bottom sheet opens and saves updated profile', (
      tester,
    ) async {
      final userRepo = _FakeUserProfileRepo();
      final notifRepo = _FakeNotificationRepo();
      final authCtrl = _StubAuthController();

      await tester.pumpWidget(
        buildApp(
          userRepo: userRepo,
          notifRepo: notifRepo,
          authCtrl: authCtrl,
          disableAnimations: true,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Edit profile'));
      await tester.pumpAndSettle();

      expect(find.text('Edit Profile'), findsOneWidget);

      await tester.enterText(find.widgetWithText(TextField, 'Sarah'), 'Jane');
      await tester.pumpAndSettle();

      await tester.tap(find.text('Save Profile'));
      await tester.pumpAndSettle();

      expect(userRepo.updateCalls, 1);
      expect(userRepo.profile.firstName, 'Jane');
    });

    testWidgets(
      'Change Password dialog validates password policy and submits',
      (tester) async {
        final userRepo = _FakeUserProfileRepo();
        final notifRepo = _FakeNotificationRepo();
        final authCtrl = _StubAuthController();

        await tester.pumpWidget(
          buildApp(
            userRepo: userRepo,
            notifRepo: notifRepo,
            authCtrl: authCtrl,
            disableAnimations: true,
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Change Password'));
        await tester.pumpAndSettle();

        expect(find.text('Update Password'), findsOneWidget);

        // Submit empty - error
        await tester.tap(find.text('Update Password'));
        await tester.pumpAndSettle();
        expect(find.text('Current password is required'), findsOneWidget);

        // Enter valid fields
        await tester.enterText(find.byType(TextField).at(0), 'oldPass');
        await tester.enterText(find.byType(TextField).at(1), 'newPassword123');
        await tester.enterText(find.byType(TextField).at(2), 'newPassword123');
        await tester.pumpAndSettle();

        await tester.tap(find.text('Update Password'));
        await tester.pumpAndSettle();

        expect(userRepo.changePasswordCalls, 1);
      },
    );

    testWidgets('Appearance ThemeMode SegmentedButton updates theme', (
      tester,
    ) async {
      final userRepo = _FakeUserProfileRepo();
      final notifRepo = _FakeNotificationRepo();
      final authCtrl = _StubAuthController();

      await tester.pumpWidget(
        buildApp(userRepo: userRepo, notifRepo: notifRepo, authCtrl: authCtrl),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Dark'));
      await tester.pumpAndSettle();

      expect(find.text('Dark'), findsOneWidget);
    });

    testWidgets('Notification channel switches toggle and save preferences', (
      tester,
    ) async {
      final userRepo = _FakeUserProfileRepo();
      final notifRepo = _FakeNotificationRepo();
      final authCtrl = _StubAuthController();

      await tester.pumpWidget(
        buildApp(
          userRepo: userRepo,
          notifRepo: notifRepo,
          authCtrl: authCtrl,
          disableAnimations: true,
        ),
      );
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(find.text('Email Alerts'), 200);
      await tester.tap(find.widgetWithText(SwitchListTile, 'Email Alerts'));
      await tester.pumpAndSettle();

      expect(notifRepo.saveSettingsCalls, 1);
    });

    testWidgets('Log out opens confirmation dialog and invokes logout', (
      tester,
    ) async {
      final userRepo = _FakeUserProfileRepo();
      final notifRepo = _FakeNotificationRepo();
      final authCtrl = _StubAuthController();

      await tester.pumpWidget(
        buildApp(
          userRepo: userRepo,
          notifRepo: notifRepo,
          authCtrl: authCtrl,
          disableAnimations: true,
        ),
      );
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.byKey(const Key('profile_logout_button')),
        300,
      );
      await tester.tap(find.byKey(const Key('profile_logout_button')));
      await tester.pumpAndSettle();

      expect(find.text('Log out?'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Log out'));
      await tester.pumpAndSettle();

      expect(authCtrl.logoutCalls, 1);
    });

    testWidgets('renders in Dark theme at 2.0x text scale without overflow', (
      tester,
    ) async {
      final userRepo = _FakeUserProfileRepo();
      final notifRepo = _FakeNotificationRepo();
      final authCtrl = _StubAuthController();

      await tester.pumpWidget(
        buildApp(
          userRepo: userRepo,
          notifRepo: notifRepo,
          authCtrl: authCtrl,
          theme: tbDarkTheme(),
          textScale: 2.0,
          disableAnimations: true,
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Profile & Settings'), findsOneWidget);
      expect(find.text('Sarah Connor'), findsOneWidget);
    });
  });

  group('Change Password dialog', () {
    final updateButton = find.widgetWithText(FilledButton, 'Update Password');

    Future<void> openDialog(WidgetTester tester, Widget app) async {
      await tester.pumpWidget(app);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Change Password'));
      await tester.pumpAndSettle();
    }

    Future<void> fill(
      WidgetTester tester, {
      String current = '',
      String next = '',
      String confirm = '',
    }) async {
      await tester.enterText(find.byType(TextField).at(0), current);
      await tester.enterText(find.byType(TextField).at(1), next);
      await tester.enterText(find.byType(TextField).at(2), confirm);
      await tester.pumpAndSettle();
    }

    Future<void> submit(WidgetTester tester) async {
      await tester.tap(updateButton);
      await tester.pumpAndSettle();
    }

    Widget app(_FakeUserProfileRepo userRepo, {UserPasswordPolicy? policy}) =>
        buildApp(
          userRepo: userRepo,
          notifRepo: _FakeNotificationRepo(),
          authCtrl: _StubAuthController(),
          disableAnimations: true,
          policy: policy,
        );

    for (final scale in const [1.0, 2.0]) {
      testWidgets(
        'submit button stays reachable above nav bar and 300dp keyboard at ${scale}x text',
        (tester) async {
          tester.view.physicalSize = const Size(360, 640);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          addTearDown(tester.view.resetViewInsets);

          final userRepo = _FakeUserProfileRepo();
          await openDialog(
            tester,
            buildShell(
              userRepo: userRepo,
              notifRepo: _FakeNotificationRepo(),
              authCtrl: _StubAuthController(),
              textScale: scale,
            ),
          );
          // Keyboard appears after the dialog is open (user taps a field).
          tester.view.viewInsets = const FakeViewPadding(bottom: 300);
          await tester.pumpAndSettle();

          expect(tester.takeException(), isNull);
          expect(updateButton.hitTestable(), findsOneWidget);
          expect(
            tester.getRect(updateButton).bottom,
            lessThanOrEqualTo(640 - 300),
          );
          await submit(tester);
          expect(tester.takeException(), isNull);
          expect(find.text('Current password is required'), findsOneWidget);
          expect(updateButton.hitTestable(), findsOneWidget);
          expect(
            tester.getRect(updateButton).bottom,
            lessThanOrEqualTo(640 - 300),
          );
          expect(userRepo.changePasswordCalls, 0);
        },
      );
    }

    testWidgets(
      'error is scrolled into view when submitting from the bottom (2.0x, keyboard)',
      (tester) async {
        tester.view.physicalSize = const Size(360, 640);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final userRepo = _FakeUserProfileRepo();
        await openDialog(
          tester,
          buildShell(
            userRepo: userRepo,
            notifRepo: _FakeNotificationRepo(),
            authCtrl: _StubAuthController(),
            textScale: 2.0,
          ),
        );
        tester.view.viewInsets = const FakeViewPadding(bottom: 300);
        addTearDown(tester.view.resetViewInsets);
        await tester.pumpAndSettle();

        await fill(
          tester,
          current: 'old',
          next: 'newPass123',
          confirm: 'newPass124',
        );
        // Scroll the form down to the Confirm field.
        await tester.ensureVisible(find.byType(TextField).at(2));
        await tester.pumpAndSettle();

        await submit(tester);

        const message = 'New passwords do not match';
        expect(tester.takeException(), isNull);
        expect(find.text(message), findsOneWidget);
        final dialog = tester.getRect(find.byType(Dialog));
        final error = tester.getRect(find.text(message));
        expect(error.top, greaterThanOrEqualTo(dialog.top));
        expect(error.bottom, lessThanOrEqualTo(dialog.bottom));
        expect(find.text(message).hitTestable(), findsOneWidget);
        expect(updateButton.hitTestable(), findsOneWidget);
        expect(userRepo.changePasswordCalls, 0);
      },
    );

    testWidgets('profile header is a TbSectionCard with name, email, badge', (
      tester,
    ) async {
      await tester.pumpWidget(app(_FakeUserProfileRepo()));
      await tester.pumpAndSettle();

      final card = find.ancestor(
        of: find.text('Account'),
        matching: find.byType(TbSectionCard),
      );
      expect(card, findsOneWidget);
      for (final text in const ['Sarah Connor', 'admin@thingsboard.org']) {
        expect(
          find.descendant(of: card, matching: find.text(text)),
          findsOneWidget,
          reason: text,
        );
      }
      expect(
        find.descendant(of: card, matching: find.byType(TbStatusBadge)),
        findsOneWidget,
      );
      final edit = tester.getSize(find.byTooltip('Edit profile'));
      expect(edit.width, greaterThanOrEqualTo(48.0));
      expect(edit.height, greaterThanOrEqualTo(48.0));
    });

    testWidgets('settings sections use the shared TbSectionCard', (
      tester,
    ) async {
      await tester.pumpWidget(app(_FakeUserProfileRepo()));
      await tester.pumpAndSettle();

      for (final title in const [
        'Security & Account',
        'Theme Mode',
        'Server & Connectivity',
        'Alarm Notification Channels',
      ]) {
        await tester.scrollUntilVisible(find.text(title), 200);
        expect(
          find.ancestor(
            of: find.text(title),
            matching: find.byType(TbSectionCard),
          ),
          findsOneWidget,
          reason: title,
        );
      }
    });

    testWidgets('is centered horizontally on screen', (tester) async {
      await openDialog(tester, app(_FakeUserProfileRepo()));

      final center = tester.getCenter(find.byType(Dialog));
      final screen = tester.getCenter(find.byType(MaterialApp));
      expect((center.dx - screen.dx).abs(), lessThan(1));
    });

    testWidgets('empty current password shows error and makes no call', (
      tester,
    ) async {
      final userRepo = _FakeUserProfileRepo();
      await openDialog(tester, app(userRepo));
      await fill(tester, next: 'secret123', confirm: 'secret123');
      await submit(tester);

      expect(find.text('Current password is required'), findsOneWidget);
      expect(userRepo.changePasswordCalls, 0);
    });

    const policy = UserPasswordPolicy(
      minimumLength: 8,
      minimumUppercaseLetters: 1,
      minimumDigits: 1,
      minimumSpecialCharacters: 1,
    );
    const policyCases = <String, String>{
      'Ab1!': 'Password must be at least 8 characters',
      'lowercase1!': 'Must contain uppercase letters',
      'Lowercase!!': 'Must contain numeric digits',
      'Lowercase1': 'Must contain special characters',
    };
    for (final c in policyCases.entries) {
      testWidgets('policy blocks "${c.key}" with "${c.value}"', (tester) async {
        final userRepo = _FakeUserProfileRepo();
        await openDialog(tester, app(userRepo, policy: policy));
        await fill(tester, current: 'old', next: c.key, confirm: c.key);
        await submit(tester);

        expect(find.text(c.value), findsOneWidget);
        expect(userRepo.changePasswordCalls, 0);
      });
    }

    testWidgets('without server policy requires 6+ characters', (tester) async {
      final userRepo = _FakeUserProfileRepo();
      await openDialog(tester, app(userRepo));
      await fill(tester, current: 'old', next: 'abc', confirm: 'abc');
      await submit(tester);

      expect(
        find.text('Password must be at least 6 characters'),
        findsOneWidget,
      );
      expect(userRepo.changePasswordCalls, 0);
    });

    testWidgets('mismatched confirmation shows error and makes no call', (
      tester,
    ) async {
      final userRepo = _FakeUserProfileRepo();
      await openDialog(tester, app(userRepo));
      await fill(
        tester,
        current: 'old',
        next: 'secret123',
        confirm: 'secret124',
      );
      await submit(tester);

      expect(find.text('New passwords do not match'), findsOneWidget);
      expect(userRepo.changePasswordCalls, 0);
    });

    testWidgets('success calls repo once, closes dialog, shows snackbar', (
      tester,
    ) async {
      final userRepo = _FakeUserProfileRepo();
      await openDialog(tester, app(userRepo));
      await fill(
        tester,
        current: 'oldPass',
        next: 'newPass123',
        confirm: 'newPass123',
      );
      await submit(tester);

      expect(userRepo.changePasswordCalls, 1);
      expect(userRepo.lastCurrentPassword, 'oldPass');
      expect(userRepo.lastNewPassword, 'newPass123');
      expect(find.byType(Dialog), findsNothing);
      expect(find.text('Password changed successfully'), findsOneWidget);
    });

    testWidgets('server rejection shows message, keeps dialog, re-enables', (
      tester,
    ) async {
      final userRepo = _FakeUserProfileRepo()
        ..changePasswordError = const TbFailure(
          type: TbFailureType.invalidCredentials,
          message: "Current password doesn't match",
        );
      await openDialog(tester, app(userRepo));
      await fill(
        tester,
        current: 'wrong',
        next: 'newPass123',
        confirm: 'newPass123',
      );
      await submit(tester);

      expect(userRepo.changePasswordCalls, 1);
      expect(find.text("Current password doesn't match"), findsOneWidget);
      expect(find.byType(Dialog), findsOneWidget);
      expect(tester.widget<FilledButton>(updateButton).onPressed, isNotNull);
    });

    testWidgets('double tap submits only once', (tester) async {
      final gate = Completer<void>();
      final userRepo = _FakeUserProfileRepo()..changePasswordGate = gate;
      await openDialog(tester, app(userRepo));
      await fill(
        tester,
        current: 'old',
        next: 'newPass123',
        confirm: 'newPass123',
      );

      await tester.tap(updateButton);
      await tester.tap(updateButton);
      await tester.pump();
      gate.complete();
      await tester.pumpAndSettle();

      expect(userRepo.changePasswordCalls, 1);
    });

    testWidgets('dismissed dialog: late success pops nothing else', (
      tester,
    ) async {
      final gate = Completer<void>();
      final userRepo = _FakeUserProfileRepo()..changePasswordGate = gate;
      await openDialog(tester, app(userRepo));
      await fill(
        tester,
        current: 'old',
        next: 'newPass123',
        confirm: 'newPass123',
      );

      await tester.tap(updateButton);
      await tester.pump();
      // Dismiss via barrier while the request is pending.
      await tester.tapAt(const Offset(2, 2));
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsNothing);

      // Open an unrelated dialog on top.
      final ctx = tester.element(find.byType(ProfileSettingsPage));
      unawaited(
        showDialog<void>(
          context: ctx,
          builder: (_) => const AlertDialog(title: Text('Other')),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Other'), findsOneWidget);

      gate.complete();
      await tester.pumpAndSettle();

      expect(userRepo.changePasswordCalls, 1);
      expect(find.text('Other'), findsOneWidget);
      expect(find.text('Password changed successfully'), findsOneWidget);
    });

    testWidgets('success during exit transition pops nothing else', (
      tester,
    ) async {
      final gate = Completer<void>();
      final userRepo = _FakeUserProfileRepo()..changePasswordGate = gate;
      await openDialog(tester, app(userRepo));
      await fill(
        tester,
        current: 'old',
        next: 'newPass123',
        confirm: 'newPass123',
      );

      await tester.tap(updateButton);
      await tester.pump();
      await tester.tapAt(const Offset(2, 2));
      await tester.pump(const Duration(milliseconds: 50));

      final ctx = tester.element(find.byType(ProfileSettingsPage));
      unawaited(
        showDialog<void>(
          context: ctx,
          builder: (_) => const AlertDialog(title: Text('Other')),
        ),
      );
      await tester.pump(const Duration(milliseconds: 50));

      gate.complete();
      await tester.pumpAndSettle();

      expect(find.text('Other'), findsOneWidget);
      expect(find.text('Password changed successfully'), findsOneWidget);
    });

    testWidgets('Cancel closes dialog without calling the API', (tester) async {
      final userRepo = _FakeUserProfileRepo();
      await openDialog(tester, app(userRepo));
      await fill(
        tester,
        current: 'old',
        next: 'newPass123',
        confirm: 'newPass123',
      );
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();

      expect(find.byType(Dialog), findsNothing);
      expect(userRepo.changePasswordCalls, 0);
    });
  });
}
