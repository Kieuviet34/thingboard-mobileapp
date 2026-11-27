import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:thingsboard_democloud_app/config/routes/router.dart';
import 'package:thingsboard_democloud_app/config/themes/design_tokens.dart';
import 'package:thingsboard_democloud_app/config/themes/tb_theme.dart';
import 'package:thingsboard_democloud_app/core/api/controllers/dashboard_controller.dart';
import 'package:thingsboard_democloud_app/core/api/controllers/server_config_controller.dart';
import 'package:thingsboard_democloud_app/core/api/controllers/telemetry_controller.dart';
import 'package:thingsboard_democloud_app/core/api/repositories/dashboard_repository.dart';
import 'package:thingsboard_democloud_app/core/api/repositories/telemetry_repository.dart';
import 'package:thingsboard_democloud_app/core/mock/mock_data.dart';
import 'package:thingsboard_democloud_app/core/models/auth_models.dart';
import 'package:thingsboard_democloud_app/core/models/dashboard_models.dart';
import 'package:thingsboard_democloud_app/core/models/entity_id.dart';
import 'package:thingsboard_democloud_app/core/models/pagination.dart';
import 'package:thingsboard_democloud_app/core/models/tb_failure.dart';
import 'package:thingsboard_democloud_app/modules/dashboard/dashboard_details_page.dart';
import 'package:thingsboard_democloud_app/modules/dashboard/dashboards_page.dart';
import 'package:thingsboard_democloud_app/widgets/icons/tb_icons.dart';
import 'package:thingsboard_democloud_app/widgets/tb_app_search_bar.dart';
import 'package:thingsboard_democloud_app/widgets/tb_empty_state.dart';
import 'package:thingsboard_democloud_app/widgets/tb_shimmer.dart';

import '../../helpers/fake_app_preferences.dart';
import '../../helpers/fake_secure_storage.dart';
import '../../helpers/fake_ws_channel.dart';

class _PagedDashboardRepo implements DashboardRepository {
  _PagedDashboardRepo({
    this.completer,
    this.shouldThrow = false,
    List<TbDashboardInfo>? items,
    this.pageSizeOverride,
  }) : _items = List<TbDashboardInfo>.from(
         items ??
             [
               const TbDashboardInfo(
                 id: 'dash-1',
                 title: 'Smart Office Monitoring',
                 isStarred: true,
                 metrics: {'Temperature': '22.4 °C', 'Humidity': '48 %'},
               ),
               const TbDashboardInfo(
                 id: 'dash-2',
                 title: 'Energy Metering',
                 isStarred: false,
                 metrics: {'Voltage': '230.8 V', 'Power': '3.81 kW'},
               ),
               const TbDashboardInfo(
                 id: 'dash-3',
                 title: 'Fleet Tracking',
                 isStarred: false,
                 metrics: {'Speed': '62 km/h'},
               ),
             ],
       );

  Completer<PageData<TbDashboardInfo>>? completer;
  bool shouldThrow;
  final int? pageSizeOverride;
  final List<TbDashboardInfo> _items;
  final List<int> requestedPages = [];
  final List<String?> requestedSearches = [];
  final List<(String, String)> reportedActions = [];

  @override
  Future<PageData<TbDashboardInfo>> getDashboards(
    PageQuery query, {
    Authority? authority,
    String? customerId,
    CancelToken? cancelToken,
  }) async {
    requestedPages.add(query.page);
    requestedSearches.add(query.textSearch);
    if (completer != null) return completer!.future;
    if (shouldThrow) {
      throw const TbFailure(
        type: TbFailureType.networkUnavailable,
        message: 'Connection lost',
      );
    }
    final search = query.textSearch?.trim().toLowerCase() ?? '';
    final filtered = _items
        .where((d) => search.isEmpty || d.title.toLowerCase().contains(search))
        .toList();
    final pageSize = pageSizeOverride ?? query.pageSize;
    final start = query.page * pageSize;
    if (start >= filtered.length) {
      return PageData<TbDashboardInfo>(
        data: const [],
        totalPages: (filtered.length / pageSize).ceil(),
        totalElements: filtered.length,
        hasNext: false,
      );
    }
    final end = (start + pageSize).clamp(0, filtered.length);
    return PageData<TbDashboardInfo>(
      data: filtered.sublist(start, end),
      totalPages: (filtered.length / pageSize).ceil(),
      totalElements: filtered.length,
      hasNext: end < filtered.length,
    );
  }

  @override
  Future<TbHomeDashboardInfo?> getHomeDashboardInfo() async =>
      const TbHomeDashboardInfo(dashboardId: 'dash-1');

  @override
  Future<UserDashboardsInfo> getLastVisitedDashboards() async =>
      const UserDashboardsInfo();

  @override
  Future<UserDashboardsInfo> reportDashboardAction(
    String dashboardId,
    String action,
  ) async {
    reportedActions.add((dashboardId, action));
    final idx = _items.indexWhere((d) => d.id == dashboardId);
    if (idx != -1) {
      if (action == 'STAR') {
        _items[idx] = _items[idx].copyWith(isStarred: true);
      } else if (action == 'UNSTAR') {
        _items[idx] = _items[idx].copyWith(isStarred: false);
      }
    }
    return const UserDashboardsInfo();
  }

  @override
  Future<TbDashboard> getDashboardById(String dashboardId) async {
    final info = _items.firstWhere(
      (d) => d.id == dashboardId,
      orElse: () => _items.first,
    );
    return TbDashboard(info: info);
  }
}

class _DemoConfigController extends ServerConfigController {
  @override
  ServerConfigState build() => const ServerConfigState(
    baseUrl: 'https://thingsboard.democloud.xyz/',
    mode: SessionMode.demo,
  );
}

void main() {
  Widget buildApp({
    required DashboardRepository repo,
    ThemeData? theme,
    Size size = const Size(390, 844),
    EdgeInsets mediaPadding = EdgeInsets.zero,
    double textScale = 1.0,
    bool disableAnimations = false,
  }) {
    final router = GoRouter(
      initialLocation: AppRoutes.dashboards,
      routes: [
        GoRoute(
          path: AppRoutes.dashboards,
          builder: (_, _) => MediaQuery(
            data: MediaQueryData(
              size: size,
              padding: mediaPadding,
              textScaler: TextScaler.linear(textScale),
              disableAnimations: disableAnimations,
            ),
            child: const DashboardsPage(),
          ),
        ),
        GoRoute(
          path: AppRoutes.dashboardDetails,
          builder: (_, state) => Scaffold(
            body: Text('OPENED_DETAIL:${state.pathParameters['id']}'),
          ),
        ),
      ],
    );

    final c = ProviderContainer();
    final mockDevices = c.read(devicesProvider);
    c.dispose();

    return ProviderScope(
      overrides: [
        tbStorageProvider.overrideWithValue(FakeSecureStorage()),
        tbAppPreferencesProvider.overrideWithValue(
          FakeAppPreferences(sessionMode: SessionMode.demo),
        ),
        wsChannelFactoryProvider.overrideWithValue(
          (_) => FakeWebSocketChannel(),
        ),
        serverConfigProvider.overrideWith(_DemoConfigController.new),
        dashboardRepositoryProvider.overrideWithValue(repo),
        telemetryRepositoryProvider.overrideWithValue(
          DemoTelemetryRepository(mockDevices),
        ),
      ],
      child: MaterialApp.router(
        theme: theme ?? tbLightTheme(),
        routerConfig: router,
      ),
    );
  }

  group('DashboardsPage widget tests', () {
    testWidgets('shows TbShimmerList while loading', (tester) async {
      final completer = Completer<PageData<TbDashboardInfo>>();
      final repo = _PagedDashboardRepo(completer: completer);

      await tester.pumpWidget(buildApp(repo: repo, disableAnimations: true));
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
      'supports All/Starred FilterChips, star toggle, search bar, and Hero tags',
      (tester) async {
        final repo = _PagedDashboardRepo();
        await tester.pumpWidget(buildApp(repo: repo, disableAnimations: true));
        await tester.pumpAndSettle();

        expect(find.text('Smart Office Monitoring'), findsOneWidget);
        expect(find.text('Energy Metering'), findsOneWidget);
        expect(find.byType(TbIcon), findsWidgets);

        // Verify Hero tag on compact single-pane card.
        final heroFinder = find.byWidgetPredicate(
          (w) => w is Hero && w.tag == 'dashboard-dash-1',
        );
        expect(heroFinder, findsOneWidget);

        // Filter to Starred.
        await tester.tap(find.widgetWithText(FilterChip, 'Starred'));
        await tester.pumpAndSettle();
        expect(find.text('Smart Office Monitoring'), findsOneWidget);
        expect(find.text('Energy Metering'), findsNothing);

        // Back to All and toggle star on Energy Metering.
        await tester.tap(find.widgetWithText(FilterChip, 'All'));
        await tester.pumpAndSettle();
        final starBtn = find.byKey(const Key('dashboard-star-dash-2'));
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
        expect(repo.reportedActions, contains(('dash-2', 'STAR')));

        // Search toggle -> TbAppSearchBar debounced query.
        await tester.tap(find.byTooltip('Search dashboards'));
        await tester.pumpAndSettle();
        expect(find.byType(TbAppSearchBar), findsOneWidget);

        await tester.enterText(find.byType(TextField), 'Fleet');
        await tester.pump(const Duration(milliseconds: 350));
        await tester.pumpAndSettle();

        expect(find.text('Fleet Tracking'), findsOneWidget);
        expect(find.text('Smart Office Monitoring'), findsNothing);
      },
    );

    testWidgets('loads next page when scrolling paginated list', (
      tester,
    ) async {
      final manyItems = [
        for (var i = 1; i <= 14; i++)
          TbDashboardInfo(
            id: 'dash-$i',
            title: 'Dashboard #$i',
            metrics: {'Temp': '${20 + i} °C'},
          ),
      ];
      final repo = _PagedDashboardRepo(items: manyItems, pageSizeOverride: 8);

      await tester.pumpWidget(buildApp(repo: repo, disableAnimations: true));
      await tester.pumpAndSettle();

      expect(repo.requestedPages, [0]);
      expect(find.text('Dashboard #1'), findsOneWidget);

      await tester.drag(find.byType(ListView), const Offset(0, -1400));
      await tester.pumpAndSettle();

      expect(repo.requestedPages, contains(1));
      await tester.scrollUntilVisible(
        find.text('Dashboard #14'),
        300,
        scrollable: find.descendant(
          of: find.byType(ListView),
          matching: find.byType(Scrollable),
        ),
      );
      expect(find.text('Dashboard #14'), findsOneWidget);
    });

    testWidgets(
      'auto-fetches subsequent pages when Starred filter has 0 matches on page 0',
      (tester) async {
        final items = [
          for (var i = 1; i <= 4; i++)
            TbDashboardInfo(
              id: 'dash-$i',
              title: 'Unstarred #$i',
              isStarred: false,
              metrics: {'Temp': '20 °C'},
            ),
          const TbDashboardInfo(
            id: 'dash-5',
            title: 'Starred On Page Two',
            isStarred: true,
            metrics: {'Temp': '25 °C'},
          ),
        ];
        final repo = _PagedDashboardRepo(items: items, pageSizeOverride: 4);

        await tester.pumpWidget(buildApp(repo: repo, disableAnimations: true));
        await tester.pumpAndSettle();

        expect(repo.requestedPages, [0]);

        await tester.tap(find.widgetWithText(FilterChip, 'Starred'));
        await tester.pumpAndSettle();

        expect(repo.requestedPages, contains(1));
        expect(find.text('Starred On Page Two'), findsOneWidget);
      },
    );

    testWidgets('shows empty state cleanly', (tester) async {
      final emptyRepo = _PagedDashboardRepo(items: const []);
      await tester.pumpWidget(
        buildApp(repo: emptyRepo, disableAnimations: true),
      );
      await tester.pumpAndSettle();
      expect(find.byType(TbEmptyState), findsOneWidget);
    });

    testWidgets('shows error state and retries cleanly', (tester) async {
      final errRepo = _PagedDashboardRepo(shouldThrow: true);
      await tester.pumpWidget(buildApp(repo: errRepo, disableAnimations: true));
      await tester.pumpAndSettle();
      expect(find.text('Retry'), findsOneWidget);

      errRepo.shouldThrow = false;
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(find.text('Smart Office Monitoring'), findsOneWidget);
    });

    testWidgets(
      'renders adaptive 2-pane master-detail on >=840dp, scopes filter bar to master pane, and preserves detail pane when Starred is empty',
      (tester) async {
        tester.view.physicalSize = const Size(1024, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        final repo = _PagedDashboardRepo(
          items: const [
            TbDashboardInfo(
              id: 'dash-1',
              title: 'Smart Office Monitoring',
              isStarred: false,
              metrics: {'Temperature': '22.4 °C'},
            ),
            TbDashboardInfo(
              id: 'dash-2',
              title: 'Energy Metering',
              isStarred: false,
              metrics: {'Voltage': '230.8 V'},
            ),
          ],
        );
        await tester.pumpWidget(
          buildApp(
            repo: repo,
            size: const Size(1024, 800),
            disableAnimations: true,
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byType(DashboardDetailsPage), findsOneWidget);
        expect(find.text('22.4 °C'), findsWidgets);

        // Filter bar stays inside the 360dp master pane; detail pane starts at body top.
        final starredChipRect = tester.getRect(
          find.widgetWithText(FilterChip, 'Starred'),
        );
        final detailRect = tester.getRect(find.byType(DashboardDetailsPage));
        expect(starredChipRect.right, lessThanOrEqualTo(360.0));
        expect(detailRect.top, lessThanOrEqualTo(starredChipRect.top));

        // Select Energy Metering in master pane -> detail pane updates.
        await tester.tap(find.byKey(const Key('dashboard-card-dash-2')));
        await tester.pumpAndSettle();
        expect(find.text('230.8 V'), findsWidgets);

        // Filtering to Starred when none are starred keeps right detail pane mounted.
        await tester.tap(find.widgetWithText(FilterChip, 'Starred'));
        await tester.pumpAndSettle();
        expect(find.text('No starred dashboards'), findsOneWidget);
        expect(find.byType(DashboardDetailsPage), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'cards maintain symmetric 16dp horizontal margins and bottom scroll clearance honors floating NavigationBar inset without viewport clipping',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        const navBarBottomInset = 76.0;
        await tester.pumpWidget(
          buildApp(
            repo: _PagedDashboardRepo(),
            size: const Size(390, 844),
            mediaPadding: const EdgeInsets.only(bottom: navBarBottomInset),
            disableAnimations: true,
          ),
        );
        await tester.pumpAndSettle();

        final cardRect = tester.getRect(
          find.byKey(const Key('dashboard-card-dash-1')),
        );
        expect(cardRect.left, DesignTokens.spacing16);
        expect(cardRect.right, 390.0 - DesignTokens.spacing16);

        final listFinder = find.byType(ListView);
        final listView = tester.widget<ListView>(listFinder);
        final resolvedPadding = (listView.padding! as EdgeInsets);
        expect(
          resolvedPadding.bottom,
          navBarBottomInset + DesignTokens.spacing16,
        );
        // Viewport reaches the bottom edge (scroll-under floating glass nav bar).
        expect(tester.getRect(listFinder).bottom, 844.0);
      },
    );

    testWidgets(
      'renders cleanly in Dark theme at 2.0x text scale with disableAnimations',
      (tester) async {
        final repo = _PagedDashboardRepo();
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
        expect(find.text('Smart Office Monitoring'), findsOneWidget);
      },
    );

    testWidgets('row shows title plus one meta line at 2.0x text scale', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildApp(
          repo: _PagedDashboardRepo(),
          textScale: 2.0,
          disableAnimations: true,
        ),
      );
      await tester.pumpAndSettle();

      final card = find.byKey(const Key('dashboard-card-dash-1'));
      final cardRect = tester.getRect(card);
      final titleRect = tester.getRect(find.text('Smart Office Monitoring'));
      expect(
        find.descendant(of: card, matching: find.byType(Text)),
        findsNWidgets(2),
      );
      expect(
        cardRect.height,
        greaterThanOrEqualTo(DesignTokens.minTouchTarget),
      );
      expect(
        titleRect.top - cardRect.top,
        greaterThanOrEqualTo(DesignTokens.spacing12),
      );
      expect(tester.takeException(), isNull);
    });
  });
}
