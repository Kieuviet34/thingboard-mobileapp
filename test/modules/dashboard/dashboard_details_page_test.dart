import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:thingsboard_democloud_app/config/themes/design_tokens.dart';
import 'package:thingsboard_democloud_app/config/themes/tb_theme.dart';
import 'package:thingsboard_democloud_app/core/api/controllers/dashboard_controller.dart';
import 'package:thingsboard_democloud_app/core/api/controllers/server_config_controller.dart';
import 'package:thingsboard_democloud_app/core/api/controllers/telemetry_controller.dart';
import 'package:thingsboard_democloud_app/core/api/repositories/dashboard_repository.dart';
import 'package:thingsboard_democloud_app/core/api/repositories/telemetry_repository.dart';
import 'package:thingsboard_democloud_app/core/models/auth_models.dart';
import 'package:thingsboard_democloud_app/core/models/dashboard_models.dart';
import 'package:thingsboard_democloud_app/core/models/entity_id.dart';
import 'package:thingsboard_democloud_app/core/models/pagination.dart';
import 'package:thingsboard_democloud_app/core/models/tb_failure.dart';
import 'package:thingsboard_democloud_app/core/models/telemetry_models.dart';
import 'package:thingsboard_democloud_app/modules/dashboard/dashboard_details_page.dart';
import 'package:thingsboard_democloud_app/widgets/tb_app_bar.dart';
import 'package:thingsboard_democloud_app/widgets/tb_empty_state.dart';
import 'package:thingsboard_democloud_app/widgets/tb_metric_pill.dart';
import 'package:thingsboard_democloud_app/widgets/tb_motion.dart';
import 'package:thingsboard_democloud_app/widgets/tb_shimmer.dart';

import '../../helpers/fake_app_preferences.dart';
import '../../helpers/fake_secure_storage.dart';
import '../../helpers/fake_ws_channel.dart';

class _DetailDashboardRepo implements DashboardRepository {
  _DetailDashboardRepo({this.completer, this.shouldThrow = false});

  Completer<TbDashboard>? completer;
  bool shouldThrow;
  final List<(String, String)> reportedActions = [];

  @override
  Future<TbDashboard> getDashboardById(String dashboardId) async {
    if (completer != null) return completer!.future;
    if (shouldThrow) {
      throw const TbFailure(
        type: TbFailureType.networkUnavailable,
        message: 'Failed to load dashboard',
      );
    }
    return const TbDashboard(
      info: TbDashboardInfo(
        id: 'dash-1',
        title: 'Smart Office Monitoring',
        isStarred: true,
        metrics: {
          'Temperature': '22.4 °C',
          'Humidity': '48 %',
          'CO2 Level': '412 ppm',
        },
      ),
    );
  }

  @override
  Future<PageData<TbDashboardInfo>> getDashboards(
    PageQuery query, {
    Authority? authority,
    String? customerId,
    CancelToken? cancelToken,
  }) async => const PageData<TbDashboardInfo>(
    data: [],
    totalPages: 0,
    totalElements: 0,
    hasNext: false,
  );

  @override
  Future<TbHomeDashboardInfo?> getHomeDashboardInfo() async => null;

  @override
  Future<UserDashboardsInfo> getLastVisitedDashboards() async =>
      const UserDashboardsInfo();

  @override
  Future<UserDashboardsInfo> reportDashboardAction(
    String dashboardId,
    String action,
  ) async {
    reportedActions.add((dashboardId, action));
    return const UserDashboardsInfo();
  }
}

class _SpyTelemetryRepo implements TelemetryRepository {
  final List<TbTsHistoryQuery> historyQueries = [];

  @override
  Future<List<TbAttributeEntry>> getAttributes(
    EntityId entityId,
    TbAttributeScope scope,
  ) async => const [];

  @override
  Future<void> saveAttributes(
    EntityId entityId,
    TbAttributeScope scope,
    Map<String, dynamic> attributes,
  ) async {}

  @override
  Future<void> deleteAttributes(
    EntityId entityId,
    TbAttributeScope scope,
    List<String> keys,
  ) async {}

  @override
  Future<Map<String, TbTsPoint>> getLatestTimeseries(
    EntityId entityId, {
    List<String>? keys,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    return {
      'temperature': TbTsPoint(
        ts: now,
        rawValue: '22.4 °C',
        numericValue: 22.4,
      ),
      'humidity': TbTsPoint(ts: now, rawValue: '48 %', numericValue: 48.0),
    };
  }

  @override
  Future<Map<String, List<TbTsPoint>>> getTimeseriesHistory(
    TbTsHistoryQuery query, {
    CancelToken? cancelToken,
  }) async {
    historyQueries.add(query);
    return {
      'temperature': [
        TbTsPoint(ts: query.startTs, rawValue: 21.0, numericValue: 21.0),
        TbTsPoint(ts: query.endTs, rawValue: 22.4, numericValue: 22.4),
      ],
      'humidity': [
        TbTsPoint(ts: query.startTs, rawValue: 45.0, numericValue: 45.0),
        TbTsPoint(ts: query.endTs, rawValue: 48.0, numericValue: 48.0),
      ],
    };
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
    required DashboardRepository dashboardRepo,
    required TelemetryRepository telemetryRepo,
    ThemeData? theme,
    double textScale = 1.0,
    bool disableAnimations = false,
    bool embedded = false,
    Future<bool> Function(Uri uri)? onOpenExternal,
  }) {
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
        dashboardRepositoryProvider.overrideWithValue(dashboardRepo),
        telemetryRepositoryProvider.overrideWithValue(telemetryRepo),
      ],
      child: MediaQuery(
        data: MediaQueryData(
          size: const Size(390, 844),
          textScaler: TextScaler.linear(textScale),
          disableAnimations: disableAnimations,
        ),
        child: MaterialApp(
          theme: theme ?? tbLightTheme(),
          home: DashboardDetailsPage(
            dashboardId: 'dash-1',
            embedded: embedded,
            onOpenExternal: onOpenExternal,
          ),
        ),
      ),
    );
  }

  group('DashboardDetailsPage widget tests', () {
    testWidgets('shows TbShimmerList while dashboard loads', (tester) async {
      final completer = Completer<TbDashboard>();
      final repo = _DetailDashboardRepo(completer: completer);
      final telRepo = _SpyTelemetryRepo();

      await tester.pumpWidget(
        buildApp(
          dashboardRepo: repo,
          telemetryRepo: telRepo,
          disableAnimations: true,
        ),
      );
      await tester.pump();

      expect(find.byType(TbShimmerList), findsOneWidget);

      completer.complete(
        const TbDashboard(
          info: TbDashboardInfo(id: 'dash-1', title: 'Smart Office'),
        ),
      );
      await tester.pumpAndSettle();
    });

    testWidgets(
      'records VISIT, shows Hero, metrics, sparklines, switches time window, toggles fullscreen & opens browser',
      (tester) async {
        final repo = _DetailDashboardRepo();
        final telRepo = _SpyTelemetryRepo();
        Uri? launchedUri;

        await tester.pumpWidget(
          buildApp(
            dashboardRepo: repo,
            telemetryRepo: telRepo,
            disableAnimations: true,
            onOpenExternal: (uri) async {
              launchedUri = uri;
              return true;
            },
          ),
        );
        await tester.pumpAndSettle();

        expect(repo.reportedActions, contains(('dash-1', 'VISIT')));
        expect(
          find.byWidgetPredicate(
            (w) => w is Hero && w.tag == 'dashboard-dash-1',
          ),
          findsOneWidget,
        );
        expect(find.byType(LivePulseDot), findsOneWidget);
        expect(find.byType(TbMetricPill), findsWidgets);
        expect(find.byType(TbSparklineChart), findsWidgets);

        // Switch time window to 7d -> reloads history with 7-day range.
        final initialCount = telRepo.historyQueries.length;
        await tester.tap(find.text('7d'));
        await tester.pumpAndSettle();
        expect(telRepo.historyQueries.length, greaterThan(initialCount));
        final lastRange =
            telRepo.historyQueries.last.endTs -
            telRepo.historyQueries.last.startTs;
        expect(
          lastRange,
          closeTo(const Duration(days: 7).inMilliseconds, 5000),
        );

        // Open in browser action has >=48dp hit target and launches expected URL.
        final openBtn = find.byTooltip('Open in browser');
        final openSize = tester.getSize(openBtn);
        expect(
          openSize.width,
          greaterThanOrEqualTo(DesignTokens.minTouchTarget),
        );
        expect(
          openSize.height,
          greaterThanOrEqualTo(DesignTokens.minTouchTarget),
        );
        await tester.tap(openBtn);
        await tester.pumpAndSettle();
        expect(
          launchedUri.toString(),
          'https://thingsboard.democloud.xyz/dashboards/dash-1',
        );

        // Toggle fullscreen on -> hides TbAppBar, shows exit FAB -> restores.
        expect(find.byType(TbAppBar), findsOneWidget);
        await tester.tap(find.byTooltip('Fullscreen'));
        await tester.pumpAndSettle();
        expect(find.byType(TbAppBar), findsNothing);
        expect(find.byTooltip('Exit fullscreen'), findsOneWidget);

        await tester.tap(find.byTooltip('Exit fullscreen'));
        await tester.pumpAndSettle();
        expect(find.byType(TbAppBar), findsOneWidget);
      },
    );

    testWidgets('shows error state and retries cleanly', (tester) async {
      final repo = _DetailDashboardRepo(shouldThrow: true);
      final telRepo = _SpyTelemetryRepo();

      await tester.pumpWidget(
        buildApp(
          dashboardRepo: repo,
          telemetryRepo: telRepo,
          disableAnimations: true,
        ),
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
        final repo = _DetailDashboardRepo();
        final telRepo = _SpyTelemetryRepo();

        await tester.pumpWidget(
          buildApp(
            dashboardRepo: repo,
            telemetryRepo: telRepo,
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
