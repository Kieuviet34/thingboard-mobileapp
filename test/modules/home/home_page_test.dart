import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:thingsboard_democloud_app/config/routes/router.dart';
import 'package:thingsboard_democloud_app/config/themes/design_tokens.dart';
import 'package:thingsboard_democloud_app/config/themes/tb_theme.dart';
import 'package:thingsboard_democloud_app/core/api/controllers/alarm_controller.dart';
import 'package:thingsboard_democloud_app/core/api/controllers/dashboard_controller.dart';
import 'package:thingsboard_democloud_app/core/api/controllers/device_controller.dart';
import 'package:thingsboard_democloud_app/core/api/controllers/server_config_controller.dart';
import 'package:thingsboard_democloud_app/core/api/repositories/alarm_repository.dart';
import 'package:thingsboard_democloud_app/core/api/repositories/dashboard_repository.dart';
import 'package:thingsboard_democloud_app/core/api/repositories/device_repository.dart';
import 'package:thingsboard_democloud_app/core/mock/mock_data.dart';
import 'package:thingsboard_democloud_app/core/models/auth_models.dart';
import 'package:thingsboard_democloud_app/core/models/dashboard_models.dart';
import 'package:thingsboard_democloud_app/core/models/entity_id.dart';
import 'package:thingsboard_democloud_app/core/models/pagination.dart';
import 'package:thingsboard_democloud_app/core/models/tb_failure.dart';
import 'package:thingsboard_democloud_app/modules/home/home_page.dart';
import 'package:thingsboard_democloud_app/widgets/icons/tb_icons.dart';
import 'package:thingsboard_democloud_app/widgets/tb_empty_state.dart';
import 'package:thingsboard_democloud_app/widgets/tb_list_row.dart';
import 'package:thingsboard_democloud_app/widgets/tb_metric_pill.dart';
import 'package:thingsboard_democloud_app/widgets/tb_section_card.dart';
import 'package:thingsboard_democloud_app/widgets/tb_shimmer.dart';
import 'package:thingsboard_democloud_app/widgets/tb_status_badge.dart';

import '../../helpers/fake_app_preferences.dart';
import '../../helpers/fake_secure_storage.dart';
import '../../helpers/fake_ws_channel.dart';

class _ControlledDashboardRepo implements DashboardRepository {
  _ControlledDashboardRepo({
    this.completer,
    this.shouldThrow = false,
    this.empty = false,
    List<TbDashboardInfo>? seed,
  }) : _items = List<TbDashboardInfo>.from(
         seed ??
             [
               const TbDashboardInfo(
                 id: 'dash-1',
                 title: 'Smart Office Monitoring',
                 isStarred: true,
                 metrics: {
                   'Temperature': '22.4 °C',
                   'Humidity': '48 %',
                   'CO2 Level': '412 ppm',
                 },
               ),
               const TbDashboardInfo(
                 id: 'dash-2',
                 title: 'Energy Metering',
                 isStarred: false,
                 metrics: {'Voltage': '230.8 V', 'Power': '3.81 kW'},
               ),
             ],
       );

  Completer<PageData<TbDashboardInfo>>? completer;
  bool shouldThrow;
  bool empty;
  final List<TbDashboardInfo> _items;
  final List<(String, String)> actions = [];

  @override
  Future<PageData<TbDashboardInfo>> getDashboards(
    PageQuery query, {
    Authority? authority,
    String? customerId,
    CancelToken? cancelToken,
  }) async {
    if (completer != null) return completer!.future;
    if (shouldThrow) {
      throw const TbFailure(
        type: TbFailureType.networkUnavailable,
        message: 'Server unreachable',
      );
    }
    if (empty) {
      return const PageData<TbDashboardInfo>(
        data: [],
        totalPages: 0,
        totalElements: 0,
        hasNext: false,
      );
    }
    return PageData<TbDashboardInfo>(
      data: List<TbDashboardInfo>.unmodifiable(_items),
      totalPages: 1,
      totalElements: _items.length,
      hasNext: false,
    );
  }

  @override
  Future<TbHomeDashboardInfo?> getHomeDashboardInfo() async {
    if (empty || shouldThrow) return null;
    return const TbHomeDashboardInfo(dashboardId: 'dash-1');
  }

  @override
  Future<UserDashboardsInfo> getLastVisitedDashboards() async {
    if (empty || shouldThrow) return const UserDashboardsInfo();
    final starred = _items
        .where((d) => d.isStarred)
        .map(
          (d) => TbUserDashboardEntry(id: d.id, title: d.title, starred: true),
        )
        .toList();
    final last = _items
        .map(
          (d) => TbUserDashboardEntry(
            id: d.id,
            title: d.title,
            starred: d.isStarred,
          ),
        )
        .toList();
    return UserDashboardsInfo(last: last, starred: starred);
  }

  @override
  Future<UserDashboardsInfo> reportDashboardAction(
    String dashboardId,
    String action,
  ) async {
    actions.add((dashboardId, action));
    final idx = _items.indexWhere((d) => d.id == dashboardId);
    if (idx != -1) {
      if (action == 'STAR') {
        _items[idx] = _items[idx].copyWith(isStarred: true);
      } else if (action == 'UNSTAR') {
        _items[idx] = _items[idx].copyWith(isStarred: false);
      }
    }
    return getLastVisitedDashboards();
  }

  @override
  Future<TbDashboard> getDashboardById(String dashboardId) async {
    final info = _items.firstWhere((d) => d.id == dashboardId);
    return TbDashboard(info: info);
  }
}

class _DemoServerConfigController extends ServerConfigController {
  @override
  ServerConfigState build() => const ServerConfigState(
    baseUrl: 'https://thingsboard.democloud.xyz/',
    mode: SessionMode.demo,
  );
}

void main() {
  Widget buildApp({
    required DashboardRepository dashboardRepo,
    ThemeData? theme,
    double textScale = 1.0,
    bool disableAnimations = false,
    Size size = const Size(390, 844),
    List<String>? navigatedLocations,
  }) {
    final router = GoRouter(
      initialLocation: AppRoutes.home,
      routes: [
        GoRoute(
          path: AppRoutes.home,
          builder: (_, _) => const HomePage(),
          routes: [
            GoRoute(
              path: 'dashboards',
              builder: (_, _) {
                navigatedLocations?.add(AppRoutes.dashboards);
                return const Scaffold(body: Text('ALL_DASHBOARDS_ROUTE'));
              },
            ),
          ],
        ),
        GoRoute(
          path: AppRoutes.dashboardDetails,
          builder: (_, state) {
            final id = state.pathParameters['id'] ?? '';
            navigatedLocations?.add('/dashboard/$id');
            return Scaffold(body: Text('DASHBOARD_DETAIL:$id'));
          },
        ),
        GoRoute(
          path: AppRoutes.alarms,
          builder: (_, _) {
            navigatedLocations?.add(AppRoutes.alarms);
            return const Scaffold(body: Text('ALARMS_ROUTE'));
          },
        ),
        GoRoute(
          path: AppRoutes.devices,
          builder: (_, _) {
            navigatedLocations?.add(AppRoutes.devices);
            return const Scaffold(body: Text('DEVICES_ROUTE'));
          },
        ),
      ],
    );

    final container = ProviderContainer();
    final mockAlarms = container.read(alarmsProvider);
    final mockDevices = container.read(devicesProvider);
    container.dispose();

    return ProviderScope(
      overrides: [
        tbStorageProvider.overrideWithValue(FakeSecureStorage()),
        tbAppPreferencesProvider.overrideWithValue(
          FakeAppPreferences(sessionMode: SessionMode.demo),
        ),
        wsChannelFactoryProvider.overrideWithValue(
          (_) => FakeWebSocketChannel(),
        ),
        serverConfigProvider.overrideWith(_DemoServerConfigController.new),
        dashboardRepositoryProvider.overrideWithValue(dashboardRepo),
        alarmRepositoryProvider.overrideWithValue(
          DemoAlarmRepository(mockAlarms),
        ),
        deviceRepositoryProvider.overrideWithValue(
          DemoDeviceRepository(mockDevices),
        ),
      ],
      child: MediaQuery(
        data: MediaQueryData(
          size: size,
          textScaler: TextScaler.linear(textScale),
          disableAnimations: disableAnimations,
        ),
        child: MaterialApp.router(
          theme: theme ?? tbLightTheme(),
          routerConfig: router,
        ),
      ),
    );
  }

  group('HomePage widget tests', () {
    testWidgets('shows TbShimmer loading state while dashboards load', (
      tester,
    ) async {
      final completer = Completer<PageData<TbDashboardInfo>>();
      final repo = _ControlledDashboardRepo(completer: completer);

      await tester.pumpWidget(
        buildApp(dashboardRepo: repo, disableAnimations: true),
      );
      await tester.pump();

      expect(find.byType(TbShimmerList), findsOneWidget);

      completer.complete(
        const PageData<TbDashboardInfo>(
          data: [],
          totalPages: 0,
          totalElements: 0,
          hasNext: false,
        ),
      );
      await tester.pumpAndSettle();
    });

    testWidgets(
      'renders DEMO badge, KPI strip, Home spotlight, metrics, and navigates on taps',
      (tester) async {
        final repo = _ControlledDashboardRepo();
        final visited = <String>[];

        await tester.pumpWidget(
          buildApp(
            dashboardRepo: repo,
            disableAnimations: true,
            navigatedLocations: visited,
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byType(TbStatusBadge), findsWidgets);
        expect(find.text('DEMO'), findsOneWidget);
        expect(find.byType(TbIcon), findsWidgets);
        expect(find.byType(TbMetricPill), findsWidgets);
        expect(find.text('Smart Office Monitoring'), findsWidgets);
        expect(find.text('Energy Metering'), findsWidgets);

        // Star toggle on Energy Metering calls STAR action.
        final starBtn = find.byKey(const Key('home-star-dash-2'));
        expect(starBtn, findsOneWidget);
        final starSize = tester.getSize(starBtn);
        expect(
          starSize.width,
          greaterThanOrEqualTo(DesignTokens.minTouchTarget),
        );
        expect(
          starSize.height,
          greaterThanOrEqualTo(DesignTokens.minTouchTarget),
        );

        await tester.tap(starBtn);
        await tester.pumpAndSettle();
        expect(repo.actions, contains(('dash-2', 'STAR')));

        // Tap Alarms KPI tile -> navigates to /alarms.
        await tester.tap(find.byKey(const Key('home-kpi-alarms')));
        await tester.pumpAndSettle();
        expect(find.text('ALARMS_ROUTE'), findsOneWidget);
        expect(visited, contains(AppRoutes.alarms));
      },
    );

    testWidgets(
      'groups content in TbSectionCard sections with TbListRow rows',
      (tester) async {
        await tester.pumpWidget(
          buildApp(
            dashboardRepo: _ControlledDashboardRepo(),
            disableAnimations: true,
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byType(TbSectionCard), findsNWidgets(3));
        for (final title in [
          'Overview',
          'Home dashboard',
          'Starred & recent',
        ]) {
          expect(
            find.descendant(
              of: find.byType(TbSectionCard),
              matching: find.text(title),
            ),
            findsOneWidget,
            reason: title,
          );
        }
        expect(
          find.descendant(
            of: find.byKey(const Key('home-kpi-alarms')),
            matching: find.byType(TbMetricPill),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: find.byKey(const Key('home-card-dash-2')),
            matching: find.byType(TbListRow),
          ),
          findsNothing,
        );
        expect(find.byKey(const Key('home-card-dash-2')), findsOneWidget);
        expect(find.byType(TbListRow), findsOneWidget);
      },
    );

    testWidgets('navigates to Devices KPI and Dashboard detail', (
      tester,
    ) async {
      final repo = _ControlledDashboardRepo();
      await tester.pumpWidget(
        buildApp(dashboardRepo: repo, disableAnimations: true),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('home-spotlight-dash-1')));
      await tester.pumpAndSettle();
      expect(find.text('DASHBOARD_DETAIL:dash-1'), findsOneWidget);
    });

    testWidgets('shows empty state when no dashboards exist', (tester) async {
      final repo = _ControlledDashboardRepo(empty: true);
      await tester.pumpWidget(
        buildApp(dashboardRepo: repo, disableAnimations: true),
      );
      await tester.pumpAndSettle();

      expect(find.byType(TbEmptyState), findsOneWidget);
      expect(find.text('No dashboards'), findsOneWidget);
    });

    testWidgets('shows error state and retries cleanly', (tester) async {
      final repo = _ControlledDashboardRepo(shouldThrow: true);
      await tester.pumpWidget(
        buildApp(dashboardRepo: repo, disableAnimations: true),
      );
      await tester.pumpAndSettle();

      expect(find.byType(TbEmptyState), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);

      repo.shouldThrow = false;
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();

      expect(find.text('Smart Office Monitoring'), findsWidgets);
    });

    testWidgets(
      'renders cleanly in Dark theme at 2.0x text scale with disableAnimations',
      (tester) async {
        final repo = _ControlledDashboardRepo();
        await tester.pumpWidget(
          buildApp(
            dashboardRepo: repo,
            theme: tbDarkTheme(),
            textScale: 2.0,
            disableAnimations: true,
          ),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.text('Smart Office Monitoring'), findsWidgets);
      },
    );
  });
}
