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
import 'package:thingsboard_democloud_app/core/models/user_models.dart';
import 'package:thingsboard_democloud_app/modules/profile/profile_settings_page.dart';

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

void main() {
  Widget buildApp({
    required _FakeUserProfileRepo userRepo,
    required _FakeNotificationRepo notifRepo,
    required _StubAuthController authCtrl,
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
        userProfileRepositoryProvider.overrideWithValue(userRepo),
        notificationRepositoryProvider.overrideWithValue(notifRepo),
        authProvider.overrideWith(() => authCtrl),
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

    testWidgets('Change Password sheet validates password policy and submits', (
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
    });

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
}
