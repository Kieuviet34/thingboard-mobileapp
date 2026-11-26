import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:thingsboard_democloud_app/config/themes/design_tokens.dart';
import 'package:thingsboard_democloud_app/config/themes/tb_theme.dart';
import 'package:thingsboard_democloud_app/core/api/controllers/dashboard_controller.dart';
import 'package:thingsboard_democloud_app/core/api/controllers/device_controller.dart';
import 'package:thingsboard_democloud_app/core/api/controllers/server_config_controller.dart';
import 'package:thingsboard_democloud_app/core/api/controllers/telemetry_controller.dart';
import 'package:thingsboard_democloud_app/core/api/repositories/dashboard_repository.dart';
import 'package:thingsboard_democloud_app/core/api/ws/telemetry_ws_service.dart';
import 'package:thingsboard_democloud_app/core/api/repositories/device_repository.dart';
import 'package:thingsboard_democloud_app/core/api/repositories/telemetry_repository.dart';
import 'package:thingsboard_democloud_app/core/models/auth_models.dart';
import 'package:thingsboard_democloud_app/core/models/dashboard_models.dart';
import 'package:thingsboard_democloud_app/core/models/device_models.dart';
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
  _DetailDashboardRepo({
    this.completer,
    this.shouldThrow = false,
    this.customDashboard,
  });

  Completer<TbDashboard>? completer;
  bool shouldThrow;
  TbDashboard? customDashboard;
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
    if (customDashboard != null) return customDashboard!;
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
  _SpyTelemetryRepo({
    this.notFoundEntityIds = const <String>{},
    this.emptyEntityIds = const <String>{},
    this.latestTs,
  });

  /// Fixed timestamp for latest points; 0 simulates an absent timestamp.
  final int? latestTs;
  final Set<String> notFoundEntityIds;
  final Set<String> emptyEntityIds;
  final List<TbTsHistoryQuery> historyQueries = [];
  final List<EntityId> latestQueries = [];

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
    latestQueries.add(entityId);
    if (notFoundEntityIds.contains(entityId.id)) {
      throw const TbFailure(
        type: TbFailureType.notFound,
        message: "Device with requested id wasn't found!",
      );
    }
    if (emptyEntityIds.contains(entityId.id)) {
      return const <String, TbTsPoint>{};
    }
    final now = latestTs ?? DateTime.now().millisecondsSinceEpoch;
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
    if (notFoundEntityIds.contains(query.entityId.id) ||
        emptyEntityIds.contains(query.entityId.id)) {
      return const <String, List<TbTsPoint>>{};
    }
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

class _StubDeviceRepo implements DeviceRepository {
  int infoCalls = 0;

  @override
  Future<PageData<TbDeviceInfo>> getDevices(
    PageQuery query,
    TbDeviceQuery filter, {
    CancelToken? cancelToken,
  }) async {
    return const PageData<TbDeviceInfo>(
      data: [
        TbDeviceInfo(
          id: 'resolved-dev-99',
          name: 'Flood Sensor B-7B05',
          type: 'Bringter Flood',
          active: true,
        ),
      ],
      totalPages: 1,
      totalElements: 1,
      hasNext: false,
    );
  }

  @override
  Future<PageData<TbDeviceProfileSummary>> getDeviceProfiles(
    PageQuery query, {
    CancelToken? cancelToken,
  }) async => const PageData<TbDeviceProfileSummary>(
    data: [],
    totalPages: 0,
    totalElements: 0,
    hasNext: false,
  );

  @override
  Future<TbDeviceInfo> getDeviceInfo(String deviceId) async {
    infoCalls++;
    return const TbDeviceInfo(
      id: 'resolved-dev-99',
      name: 'Flood',
      type: 'Sensor',
    );
  }

  @override
  Future<TbDeviceCredentials> getDeviceCredentials(String deviceId) async =>
      const TbDeviceCredentials(
        id: 'c-1',
        deviceId: 'resolved-dev-99',
        credentialsType: 'ACCESS_TOKEN',
        credentialsId: 'tok',
      );

  @override
  Future<TbClaimResult> claimDevice(
    String deviceName, {
    String? secretKey,
  }) async => const TbClaimResult(response: 'SUCCESS');
}

class _DemoConfigController extends ServerConfigController {
  @override
  ServerConfigState build() => const ServerConfigState(
    baseUrl: 'https://thingsboard.democloud.xyz/',
    mode: SessionMode.demo,
  );
}

class _LiveConfigController extends ServerConfigController {
  @override
  ServerConfigState build() => const ServerConfigState(
    baseUrl: 'https://thingsboard.democloud.xyz/',
    mode: SessionMode.live,
  );
}

void main() {
  Widget buildApp({
    required DashboardRepository dashboardRepo,
    required TelemetryRepository telemetryRepo,
    DeviceRepository? deviceRepo,
    SessionMode mode = SessionMode.demo,
    String dashboardId = 'dash-1',
    ThemeData? theme,
    double textScale = 1.0,
    bool disableAnimations = false,
    bool embedded = false,
    Future<bool> Function(Uri uri)? onOpenExternal,
    List<Override> extraOverrides = const [],
  }) {
    return ProviderScope(
      overrides: [
        ...extraOverrides,
        tbStorageProvider.overrideWithValue(FakeSecureStorage()),
        tbAppPreferencesProvider.overrideWithValue(
          FakeAppPreferences(sessionMode: mode),
        ),
        wsChannelFactoryProvider.overrideWithValue(
          (_) => FakeWebSocketChannel(),
        ),
        serverConfigProvider.overrideWith(
          mode == SessionMode.live
              ? _LiveConfigController.new
              : _DemoConfigController.new,
        ),
        dashboardRepositoryProvider.overrideWithValue(dashboardRepo),
        telemetryRepositoryProvider.overrideWithValue(telemetryRepo),
        if (deviceRepo != null)
          deviceRepositoryProvider.overrideWithValue(deviceRepo),
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
            dashboardId: dashboardId,
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

    testWidgets(
      'resolves dynamic deviceType alias in Live mode and renders REST latest telemetry pills',
      (tester) async {
        final repo = _DetailDashboardRepo(
          customDashboard: const TbDashboard(
            info: TbDashboardInfo(
              id: '5f1b2c30-0000-11ee-be56-0242ac120002',
              title: 'Flood Monitoring',
            ),
            configuration: {
              'entityAliases': {
                'a1': {
                  'alias': 'Flood Sensors',
                  'filter': {
                    'type': 'deviceType',
                    'deviceType': 'Bringter Flood',
                  },
                },
              },
            },
          ),
        );
        final telRepo = _SpyTelemetryRepo();
        final devRepo = _StubDeviceRepo();

        await tester.pumpWidget(
          buildApp(
            dashboardRepo: repo,
            telemetryRepo: telRepo,
            deviceRepo: devRepo,
            mode: SessionMode.live,
            dashboardId: '5f1b2c30-0000-11ee-be56-0242ac120002',
            disableAnimations: true,
          ),
        );
        await tester.pumpAndSettle();

        expect(
          telRepo.latestQueries,
          contains(
            const EntityId(
              entityType: EntityType.device,
              id: 'resolved-dev-99',
            ),
          ),
        );
        expect(find.text('22.4 °C'), findsOneWidget);
      },
    );

    testWidgets(
      'skips orphaned/deleted static entityAliases (404) and resolves widget-referenced active device telemetry',
      (tester) async {
        final repo = _DetailDashboardRepo(
          customDashboard: const TbDashboard(
            info: TbDashboardInfo(
              id: '115fbd20-df2f-11f1-991a-2ba0e9cc8ebb',
              title: 'Bringter_flood_test_5DVC',
            ),
            configuration: {
              'entityAliases': {
                'orphaned-alias': {
                  'id': 'orphaned-alias',
                  'alias': 'bringter_flood_deleted',
                  'filter': {
                    'type': 'singleEntity',
                    'singleEntity': {
                      'entityType': 'DEVICE',
                      'id': '4fcc1870-b1a2-11f1-8553-d97f9e4a8828',
                    },
                  },
                },
                'alias-004-empty': {
                  'id': 'alias-004-empty',
                  'alias': 'Bringter_flood_004',
                  'filter': {
                    'type': 'singleEntity',
                    'singleEntity': {
                      'entityType': 'DEVICE',
                      'id': '380b3b80-df1a-11f1-991a-2ba0e9cc8ebb',
                    },
                  },
                },
                'alias-003-live': {
                  'id': 'alias-003-live',
                  'alias': 'Bringter_flood_003',
                  'filter': {
                    'type': 'singleEntity',
                    'singleEntity': {
                      'entityType': 'DEVICE',
                      'id': '321a1570-df1a-11f1-991a-2ba0e9cc8ebb',
                    },
                  },
                },
              },
              'widgets': {
                'w1': {
                  'config': {
                    'datasources': [
                      {
                        'type': 'entity',
                        'entityAliasId': 'alias-004-empty',
                        'dataKeys': [
                          {'name': 'battery_mv', 'type': 'timeseries'},
                        ],
                      },
                    ],
                  },
                },
                'w2': {
                  'config': {
                    'datasources': [
                      {
                        'type': 'entity',
                        'entityAliasId': 'alias-003-live',
                        'dataKeys': [
                          {'name': 'water_level_cm', 'type': 'timeseries'},
                        ],
                      },
                    ],
                  },
                },
              },
            },
          ),
        );
        final telRepo = _SpyTelemetryRepo(
          notFoundEntityIds: const {'4fcc1870-b1a2-11f1-8553-d97f9e4a8828'},
          emptyEntityIds: const {'380b3b80-df1a-11f1-991a-2ba0e9cc8ebb'},
        );
        final devRepo = _StubDeviceRepo();

        await tester.pumpWidget(
          buildApp(
            dashboardRepo: repo,
            telemetryRepo: telRepo,
            deviceRepo: devRepo,
            mode: SessionMode.live,
            dashboardId: '115fbd20-df2f-11f1-991a-2ba0e9cc8ebb',
            disableAnimations: true,
          ),
        );
        await tester.pumpAndSettle();

        // Orphaned alias must never be queried when widgets reference valid aliases!
        expect(
          telRepo.latestQueries,
          isNot(
            contains(
              const EntityId(
                entityType: EntityType.device,
                id: '4fcc1870-b1a2-11f1-8553-d97f9e4a8828',
              ),
            ),
          ),
        );
        // Active widget-referenced device 003 with non-empty telemetry is selected and rendered!
        expect(find.text('22.4 °C'), findsOneWidget);
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

    testWidgets(
      'summary header shows title, DEMO badge, metric count, last update',
      (tester) async {
        await tester.pumpWidget(
          buildApp(
            dashboardRepo: _DetailDashboardRepo(),
            telemetryRepo: _SpyTelemetryRepo(),
            disableAnimations: true,
          ),
        );
        await tester.pumpAndSettle();

        final header = find.byKey(const Key('dashboard-summary'));
        expect(header, findsOneWidget);
        expect(
          find.descendant(
            of: header,
            matching: find.text('Smart Office Monitoring'),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(of: header, matching: find.text('DEMO')),
          findsOneWidget,
        );
        expect(
          tester
              .widget<Text>(find.byKey(const Key('dashboard-summary-metrics')))
              .data,
          '3',
        );
        final updated = tester
            .widget<Text>(find.byKey(const Key('dashboard-summary-updated')))
            .data;
        expect(updated, matches(RegExp(r'^\d{4}-\d{2}-\d{2} \d{2}:\d{2}$')));
      },
    );

    testWidgets('metric values use tabular figures and keep stable order', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildApp(
          dashboardRepo: _DetailDashboardRepo(),
          telemetryRepo: _SpyTelemetryRepo(),
          disableAnimations: true,
        ),
      );
      await tester.pumpAndSettle();

      final value = tester.widget<Text>(find.text('22.4 °C'));
      expect(
        value.style?.fontFeatures,
        contains(const FontFeature.tabularFigures()),
      );
      final ys = [
        for (final label in ['Temperature', 'Humidity', 'CO2 Level'])
          tester.getTopLeft(find.text(label)).dy,
      ];
      expect(ys, orderedEquals([...ys]..sort()));
    });

    testWidgets(
      'embedded header with actions has no overflow at 2.0x text scale',
      (tester) async {
        await tester.pumpWidget(
          buildApp(
            dashboardRepo: _DetailDashboardRepo(),
            telemetryRepo: _SpyTelemetryRepo(),
            embedded: true,
            textScale: 2.0,
            disableAnimations: true,
          ),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.byTooltip('Fullscreen'), findsOneWidget);
      },
    );

    // Live fixture: dashboard title ('Flood Monitoring') differs from the
    // resolved device name; stream state is faked by overriding
    // wsConnectionStateProvider with an authenticated stream.
    final liveStreamOverride = wsConnectionStateProvider.overrideWith(
      (ref) => Stream.value(WsConnectionState.authenticated),
    );
    const liveId = '5f1b2c30-0000-11ee-be56-0242ac120002';

    for (final (state, badge, other) in [
      (WsConnectionState.authenticated, 'LIVE', 'OFFLINE'),
      (WsConnectionState.disconnected, 'OFFLINE', 'LIVE'),
    ]) {
      testWidgets('live header shows $badge badge when stream is $state', (
        tester,
      ) async {
        final devRepo = _StubDeviceRepo();
        await tester.pumpWidget(
          buildApp(
            dashboardRepo: _DetailDashboardRepo(
              customDashboard: const TbDashboard(
                info: TbDashboardInfo(
                  id: '5f1b2c30-0000-11ee-be56-0242ac120002',
                  title: 'Flood Monitoring',
                ),
                configuration: {
                  'entityAliases': {
                    'a1': {
                      'alias': 'Flood Sensors',
                      'filter': {
                        'type': 'deviceType',
                        'deviceType': 'Bringter Flood',
                      },
                    },
                  },
                },
              ),
            ),
            telemetryRepo: _SpyTelemetryRepo(),
            deviceRepo: devRepo,
            mode: SessionMode.live,
            dashboardId: liveId,
            disableAnimations: true,
            extraOverrides: [
              wsConnectionStateProvider.overrideWith(
                (ref) => Stream.value(state),
              ),
            ],
          ),
        );
        await tester.pumpAndSettle();

        final header = find.byKey(const Key('dashboard-summary'));
        expect(header, findsOneWidget);
        expect(
          find.descendant(of: header, matching: find.text('Flood Monitoring')),
          findsOneWidget,
        );
        // Target name comes from the already-loaded device list: no extra
        // getDeviceInfo request, and the dashboard title stays the card title.
        expect(devRepo.infoCalls, 0);
        expect(
          find.descendant(
            of: header,
            matching: find.byKey(const Key('dashboard-summary-target')),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: header,
            matching: find.text('Flood Sensor B-7B05'),
          ),
          findsOneWidget,
        );
        expect(
          tester.widget<LivePulseDot>(find.byType(LivePulseDot)).active,
          state == WsConnectionState.authenticated,
        );
        expect(
          find.descendant(of: header, matching: find.text(badge)),
          findsOneWidget,
        );
        // The badge describes the stream, never the device.
        for (final label in ['ONLINE', other, 'DEMO']) {
          expect(
            find.descendant(of: header, matching: find.text(label)),
            findsNothing,
          );
        }
      });
    }

    testWidgets(
      'live update with reordered keys keeps card order, refreshes values',
      (tester) async {
        final updates = StreamController<Map<String, TbTsPoint>>.broadcast();
        addTearDown(updates.close);
        await tester.pumpWidget(
          buildApp(
            dashboardRepo: _DetailDashboardRepo(
              customDashboard: const TbDashboard(
                info: TbDashboardInfo(
                  id: '5f1b2c30-0000-11ee-be56-0242ac120002',
                  title: 'Flood Monitoring',
                ),
                configuration: {
                  'entityAliases': {
                    'a1': {
                      'alias': 'Flood Sensors',
                      'filter': {
                        'type': 'deviceType',
                        'deviceType': 'Bringter Flood',
                      },
                    },
                  },
                },
              ),
            ),
            telemetryRepo: _SpyTelemetryRepo(),
            deviceRepo: _StubDeviceRepo(),
            mode: SessionMode.live,
            dashboardId: liveId,
            disableAnimations: true,
            extraOverrides: [
              liveStreamOverride,
              liveEntityTelemetryProvider.overrideWith(
                (ref, params) => updates.stream,
              ),
            ],
          ),
        );
        await tester.pumpAndSettle();

        // Row-major position: cards may share a row on wide surfaces.
        double y(String label) {
          final o = tester.getTopLeft(find.text(label));
          return o.dy * 10000 + o.dx;
        }

        expect(y('temperature'), lessThan(y('humidity')));
        expect(find.text('22.4 °C'), findsOneWidget);

        final ts = DateTime.now().millisecondsSinceEpoch;
        updates.add({
          'humidity': TbTsPoint(ts: ts, rawValue: '51 %', numericValue: 51.0),
          'temperature': TbTsPoint(
            ts: ts,
            rawValue: '23.1 °C',
            numericValue: 23.1,
          ),
        });
        await tester.pumpAndSettle();

        expect(y('temperature'), lessThan(y('humidity')));
        expect(find.text('23.1 °C'), findsOneWidget);
        expect(find.text('51 %'), findsOneWidget);
        expect(find.text('22.4 °C'), findsNothing);
        expect(find.text('48 %'), findsNothing);
      },
    );

    testWidgets('last update shows exact formatted time, hidden when absent', (
      tester,
    ) async {
      final known = DateTime(2026, 3, 4, 9, 7);
      await tester.pumpWidget(
        buildApp(
          dashboardRepo: _DetailDashboardRepo(),
          telemetryRepo: _SpyTelemetryRepo(
            latestTs: known.millisecondsSinceEpoch,
          ),
          disableAnimations: true,
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<Text>(find.byKey(const Key('dashboard-summary-updated')))
            .data,
        '2026-03-04 09:07',
      );

      await tester.pumpWidget(
        buildApp(
          dashboardRepo: _DetailDashboardRepo(),
          telemetryRepo: _SpyTelemetryRepo(latestTs: 0),
          disableAnimations: true,
          dashboardId: 'dash-1',
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('dashboard-summary')), findsOneWidget);
      expect(find.byKey(const Key('dashboard-summary-updated')), findsNothing);
    });
  });
}
