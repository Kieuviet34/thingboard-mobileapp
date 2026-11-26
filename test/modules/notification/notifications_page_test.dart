import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:thingsboard_democloud_app/config/themes/tb_theme.dart';
import 'package:thingsboard_democloud_app/core/api/controllers/notification_controller.dart';
import 'package:thingsboard_democloud_app/core/api/controllers/server_config_controller.dart';
import 'package:thingsboard_democloud_app/core/api/repositories/notification_repository.dart';
import 'package:thingsboard_democloud_app/core/models/alarm_models.dart';
import 'package:thingsboard_democloud_app/core/models/notification_models.dart';
import 'package:thingsboard_democloud_app/core/models/pagination.dart';
import 'package:thingsboard_democloud_app/core/models/tb_failure.dart';
import 'package:thingsboard_democloud_app/modules/notification/notifications_page.dart';
import 'package:thingsboard_democloud_app/widgets/icons/tb_icons.dart';
import 'package:thingsboard_democloud_app/widgets/tb_empty_state.dart';
import 'package:thingsboard_democloud_app/widgets/tb_list_row.dart';
import 'package:thingsboard_democloud_app/widgets/tb_status_badge.dart';

import '../../helpers/fake_app_preferences.dart';
import '../../helpers/fake_secure_storage.dart';
import '../../helpers/fake_ws_channel.dart';
import '../../helpers/mock_dio_adapter.dart';

class _FakeNotificationRepo implements NotificationRepository {
  _FakeNotificationRepo({List<TbNotification>? initial})
    : items = initial ?? [];

  List<TbNotification> items;
  TbFailure? throwFailure;
  int markAsReadCalls = 0;
  int markAllAsReadCalls = 0;
  int deleteCalls = 0;

  @override
  Future<PageData<TbNotification>> getNotifications(
    PageQuery query, {
    bool unreadOnly = false,
    CancelToken? cancelToken,
  }) async {
    if (throwFailure != null) throw throwFailure!;

    final filtered = items.where((n) {
      if (unreadOnly && n.isRead) return false;
      return true;
    }).toList();

    return PageData<TbNotification>(
      data: filtered,
      totalPages: 1,
      totalElements: filtered.length,
      hasNext: false,
    );
  }

  @override
  Future<int> getUnreadCount() async => items.where((n) => !n.isRead).length;

  @override
  Future<void> markAsRead(String notificationId) async {
    markAsReadCalls++;
    final idx = items.indexWhere((n) => n.id == notificationId);
    if (idx != -1) {
      items[idx] = items[idx].copyWith(isRead: true);
    }
  }

  @override
  Future<void> markAllAsRead() async {
    markAllAsReadCalls++;
    items = [for (final n in items) n.copyWith(isRead: true)];
  }

  @override
  Future<void> deleteNotification(String notificationId) async {
    deleteCalls++;
    items.removeWhere((n) => n.id == notificationId);
  }

  @override
  Future<TbUserNotificationSettings> getNotificationSettings() async =>
      const TbUserNotificationSettings();

  @override
  Future<TbUserNotificationSettings> saveNotificationSettings(
    TbUserNotificationSettings settings,
  ) async => settings;

  @override
  Future<void> registerMobileSession(String fcmToken) async {}

  @override
  Future<void> removeMobileSession(String fcmToken) async {}
}

final _sampleNotifications = [
  const TbNotification(
    id: 'n-1',
    subject: 'Critical: Inverter Offline',
    text: 'Solar Inverter 01 lost connection',
    createdTime: 1700000000000,
    isRead: false,
    severity: AlarmSeverity.critical,
  ),
  const TbNotification(
    id: 'n-2',
    subject: 'System Maintenance Scheduled',
    text: 'Upgrades planned for Sunday at midnight',
    createdTime: 1700000100000,
    isRead: true,
  ),
];

void main() {
  Widget buildApp({
    required NotificationRepository repo,
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
        notificationRepositoryProvider.overrideWithValue(repo),
      ],
      child: MediaQuery(
        data: MediaQueryData(
          size: const Size(390, 844),
          textScaler: TextScaler.linear(textScale),
          disableAnimations: disableAnimations,
        ),
        child: MaterialApp(
          theme: theme ?? tbLightTheme(),
          home: const NotificationsPage(),
        ),
      ),
    );
  }

  group('NotificationsPage', () {
    testWidgets(
      'renders inbox notifications and toggles between All and Unread',
      (tester) async {
        final repo = _FakeNotificationRepo(
          initial: List.of(_sampleNotifications),
        );
        await tester.pumpWidget(buildApp(repo: repo));
        await tester.pumpAndSettle();

        expect(find.text('Notifications'), findsOneWidget);
        expect(find.text('Critical: Inverter Offline'), findsOneWidget);
        expect(find.text('System Maintenance Scheduled'), findsOneWidget);
        expect(find.byType(TbIcon), findsWidgets);

        // Toggle to Unread
        await tester.tap(find.text('Unread'));
        await tester.pumpAndSettle();

        expect(find.text('Critical: Inverter Offline'), findsOneWidget);
        expect(find.text('System Maintenance Scheduled'), findsNothing);
      },
    );

    testWidgets('rows use TbListRow with channel meta and unread badge', (
      tester,
    ) async {
      final repo = _FakeNotificationRepo(
        initial: List.of(_sampleNotifications),
      );
      await tester.pumpWidget(buildApp(repo: repo));
      await tester.pumpAndSettle();

      expect(find.byType(TbListRow), findsNWidgets(2));
      final rows = tester.widgetList<TbListRow>(find.byType(TbListRow));
      for (final row in rows) {
        expect(row.meta, endsWith(' · WEB'));
      }
      expect(
        find.byKey(const ValueKey('notification-unread-n-1')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('notification-unread-n-2')),
        findsNothing,
      );
      expect(find.byType(TbStatusBadge), findsOneWidget);

      await tester.tap(find.text('Critical: Inverter Offline'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('notification-unread-n-1')),
        findsNothing,
      );
    });

    testWidgets('mark all as read action triggers repository call', (
      tester,
    ) async {
      final repo = _FakeNotificationRepo(
        initial: List.of(_sampleNotifications),
      );
      await tester.pumpWidget(buildApp(repo: repo));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Mark all as read'));
      await tester.pumpAndSettle();

      expect(repo.markAllAsReadCalls, 1);
    });

    testWidgets('tapping an unread notification marks it as read', (
      tester,
    ) async {
      final repo = _FakeNotificationRepo(
        initial: List.of(_sampleNotifications),
      );
      await tester.pumpWidget(buildApp(repo: repo));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Critical: Inverter Offline'));
      await tester.pumpAndSettle();

      expect(repo.markAsReadCalls, 1);
    });

    testWidgets('multi-select mode allows selecting and deleting items', (
      tester,
    ) async {
      final repo = _FakeNotificationRepo(
        initial: List.of(_sampleNotifications),
      );
      await tester.pumpWidget(buildApp(repo: repo));
      await tester.pumpAndSettle();

      // Long press first item to enter multi-select
      await tester.longPress(find.text('Critical: Inverter Offline'));
      await tester.pumpAndSettle();

      expect(find.text('1 selected'), findsOneWidget);
      expect(find.byTooltip('Delete selected'), findsOneWidget);

      await tester.tap(find.byTooltip('Delete selected'));
      await tester.pumpAndSettle();

      expect(repo.deleteCalls, 1);
      expect(find.text('1 selected'), findsNothing);
    });

    testWidgets('empty unread list renders empty state', (tester) async {
      final repo = _FakeNotificationRepo(initial: []);
      await tester.pumpWidget(buildApp(repo: repo));
      await tester.pumpAndSettle();

      expect(find.byType(TbEmptyState), findsOneWidget);
      expect(find.text('Inbox is empty'), findsOneWidget);
    });

    testWidgets('renders in Dark theme at 2.0x text scale without overflow', (
      tester,
    ) async {
      final repo = _FakeNotificationRepo(
        initial: List.of(_sampleNotifications),
      );
      await tester.pumpWidget(
        buildApp(
          repo: repo,
          theme: tbDarkTheme(),
          textScale: 2.0,
          disableAnimations: true,
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Notifications'), findsOneWidget);
    });
  });
}
