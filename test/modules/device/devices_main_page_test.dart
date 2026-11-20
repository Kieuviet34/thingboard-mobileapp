import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:thingsboard_democloud_app/config/routes/router.dart';
import 'package:thingsboard_democloud_app/config/themes/tb_theme.dart';
import 'package:thingsboard_democloud_app/core/api/controllers/device_controller.dart';
import 'package:thingsboard_democloud_app/core/api/controllers/server_config_controller.dart';
import 'package:thingsboard_democloud_app/core/api/repositories/device_repository.dart';
import 'package:thingsboard_democloud_app/core/models/device_models.dart';
import 'package:thingsboard_democloud_app/core/models/pagination.dart';
import 'package:thingsboard_democloud_app/core/models/tb_failure.dart';
import 'package:thingsboard_democloud_app/modules/device/devices_main_page.dart';
import 'package:thingsboard_democloud_app/widgets/tb_empty_state.dart';
import 'package:thingsboard_democloud_app/widgets/tb_shimmer.dart';

import '../../helpers/fake_app_preferences.dart';
import '../../helpers/fake_secure_storage.dart';
import '../../helpers/fake_ws_channel.dart';

class _ControlledDeviceRepo implements DeviceRepository {
  _ControlledDeviceRepo({List<TbDeviceProfileSummary>? profiles})
    : profiles = List<TbDeviceProfileSummary>.from(
        profiles ??
            [
              const TbDeviceProfileSummary(
                id: 'prof-1',
                name: 'Thermometer',
                activeCount: 3,
                inactiveCount: 2,
              ),
              const TbDeviceProfileSummary(
                id: 'prof-2',
                name: 'Smart Meter',
                activeCount: 6,
                inactiveCount: 2,
              ),
              const TbDeviceProfileSummary(
                id: 'prof-3',
                name: 'Air Quality Sensor',
                activeCount: 1,
                inactiveCount: 2,
              ),
            ],
      );

  Completer<PageData<TbDeviceProfileSummary>>? completer;
  bool shouldThrow = false;
  final List<TbDeviceProfileSummary> profiles;

  @override
  Future<PageData<TbDeviceProfileSummary>> getDeviceProfiles(
    PageQuery query, {
    CancelToken? cancelToken,
  }) async {
    if (completer != null) return completer!.future;
    if (shouldThrow) {
      throw const TbFailure(
        type: TbFailureType.networkUnavailable,
        message: 'Network connection failed',
      );
    }
    return PageData(
      data: profiles,
      totalPages: 1,
      totalElements: profiles.length,
      hasNext: false,
    );
  }

  @override
  Future<PageData<TbDeviceInfo>> getDevices(
    PageQuery query,
    TbDeviceQuery filter, {
    CancelToken? cancelToken,
  }) async {
    return const PageData(
      data: [],
      totalPages: 0,
      totalElements: 0,
      hasNext: false,
    );
  }

  @override
  Future<TbDeviceInfo> getDeviceInfo(String deviceId) async {
    throw UnimplementedError();
  }

  @override
  Future<TbDeviceCredentials> getDeviceCredentials(String deviceId) async {
    throw UnimplementedError();
  }

  @override
  Future<TbClaimResult> claimDevice(
    String deviceName, {
    String? secretKey,
  }) async {
    return const TbClaimResult(response: 'SUCCESS');
  }
}

void main() {
  late FakeAppPreferences prefs;
  late FakeSecureStorage storage;
  late _ControlledDeviceRepo repo;
  final List<String> pushedRoutes = [];

  setUp(() {
    prefs = FakeAppPreferences();
    storage = FakeSecureStorage();
    repo = _ControlledDeviceRepo();
    pushedRoutes.clear();
  });

  List<Override> buildOverrides() => [
    tbAppPreferencesProvider.overrideWithValue(prefs),
    tbStorageProvider.overrideWithValue(storage),
    wsChannelFactoryProvider.overrideWithValue((_) => FakeWebSocketChannel()),
    deviceRepositoryProvider.overrideWithValue(repo),
  ];

  GoRouter createTestRouter() {
    return GoRouter(
      initialLocation: AppRoutes.devices,
      routes: [
        GoRoute(
          path: AppRoutes.devices,
          builder: (context, state) => const DevicesMainPage(),
        ),
        GoRoute(
          path: AppRoutes.deviceList,
          builder: (context, state) {
            pushedRoutes.add(state.uri.toString());
            return Scaffold(
              body: Text('DEVICE_LIST_PAGE:${state.uri.toString()}'),
            );
          },
        ),
        GoRoute(
          path: AppRoutes.qrScan,
          builder: (context, state) {
            pushedRoutes.add(AppRoutes.qrScan);
            return const Scaffold(body: Text('QR_SCAN_PAGE'));
          },
        ),
      ],
    );
  }

  Widget buildTestWidget(
    WidgetTester tester, {
    GoRouter? router,
    ThemeData? theme,
    double textScale = 1.0,
    bool disableAnimations = false,
  }) {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final testRouter = router ?? createTestRouter();

    return ProviderScope(
      overrides: buildOverrides(),
      child: MediaQuery(
        data: MediaQueryData(
          size: const Size(800, 1200),
          textScaler: TextScaler.linear(textScale),
          disableAnimations: disableAnimations,
        ),
        child: MaterialApp.router(
          theme: theme ?? tbLightTheme(),
          routerConfig: testRouter,
        ),
      ),
    );
  }

  group('DevicesMainPage Widget Tests', () {
    testWidgets('renders loading shimmer on initial build', (
      WidgetTester tester,
    ) async {
      repo.completer = Completer<PageData<TbDeviceProfileSummary>>();

      await tester.pumpWidget(buildTestWidget(tester));
      await tester.pump();

      expect(find.byType(TbShimmerList), findsOneWidget);
    });

    testWidgets('renders error state and retries successfully', (
      WidgetTester tester,
    ) async {
      repo.shouldThrow = true;

      await tester.pumpWidget(buildTestWidget(tester));
      await tester.pumpAndSettle();

      expect(find.byType(TbEmptyState), findsOneWidget);
      expect(find.text('Failed to load devices'), findsOneWidget);
      expect(find.text('Network connection failed'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);

      repo.shouldThrow = false;
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();

      expect(find.text('All devices'), findsOneWidget);
      expect(find.text('Thermometer'), findsOneWidget);
    });

    testWidgets('renders empty state when no device profiles exist', (
      WidgetTester tester,
    ) async {
      repo.profiles.clear();

      await tester.pumpWidget(buildTestWidget(tester));
      await tester.pumpAndSettle();

      expect(find.byType(TbEmptyState), findsOneWidget);
      expect(find.text('No device profiles'), findsOneWidget);
      expect(find.text('Claim or add a device to get started'), findsOneWidget);
    });

    testWidgets('renders summary tile with total, online, and offline counts', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(buildTestWidget(tester));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('all-devices-summary-card')), findsOneWidget);
      expect(find.text('All devices'), findsOneWidget);
      // Total = (3+2) + (6+2) + (1+2) = 16 total
      expect(find.text('16 total'), findsOneWidget);
      // Online = 3 + 6 + 1 = 10 Online
      expect(find.text('10 Online'), findsOneWidget);
      // Offline = 2 + 2 + 2 = 6 Offline
      expect(find.text('6 Offline'), findsOneWidget);
    });

    testWidgets('renders device profile cards with correct names and counts', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(buildTestWidget(tester));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('device-profile-card-prof-1')),
        findsOneWidget,
      );
      expect(find.text('Thermometer'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const Key('device-profile-card-prof-1')),
          matching: find.text('3'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('device-profile-card-prof-1')),
          matching: find.text('2'),
        ),
        findsOneWidget,
      );

      expect(
        find.byKey(const Key('device-profile-card-prof-2')),
        findsOneWidget,
      );
      expect(find.text('Smart Meter'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const Key('device-profile-card-prof-2')),
          matching: find.text('6'),
        ),
        findsOneWidget,
      );

      expect(
        find.byKey(const Key('device-profile-card-prof-3')),
        findsOneWidget,
      );
      expect(find.text('Air Quality Sensor'), findsOneWidget);
    });

    testWidgets(
      'navigates to device list with search enabled on search button tap',
      (WidgetTester tester) async {
        await tester.pumpWidget(buildTestWidget(tester));
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('devices-main-search-button')));
        await tester.pumpAndSettle();

        expect(
          pushedRoutes.any(
            (r) =>
                r.contains(AppRoutes.deviceList) && r.contains('search=true'),
          ),
          isTrue,
        );
        expect(find.textContaining('DEVICE_LIST_PAGE:'), findsOneWidget);
      },
    );

    testWidgets('navigates to qr scan on qr button tap', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(buildTestWidget(tester));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('devices-main-qr-button')));
      await tester.pumpAndSettle();

      expect(pushedRoutes, contains(AppRoutes.qrScan));
      expect(find.text('QR_SCAN_PAGE'), findsOneWidget);
    });

    testWidgets('navigates to device list on summary tile tap', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(buildTestWidget(tester));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('all-devices-summary-card')));
      await tester.pumpAndSettle();

      expect(pushedRoutes, contains(AppRoutes.deviceList));
    });

    testWidgets(
      'navigates to device list filtered by online on online pill tap',
      (WidgetTester tester) async {
        await tester.pumpWidget(buildTestWidget(tester));
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('all-devices-online-pill')));
        await tester.pumpAndSettle();

        expect(
          pushedRoutes.any(
            (r) =>
                r.contains(AppRoutes.deviceList) && r.contains('active=true'),
          ),
          isTrue,
        );
      },
    );

    testWidgets(
      'navigates to device list filtered by offline on offline pill tap',
      (WidgetTester tester) async {
        await tester.pumpWidget(buildTestWidget(tester));
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('all-devices-offline-pill')));
        await tester.pumpAndSettle();

        expect(
          pushedRoutes.any(
            (r) =>
                r.contains(AppRoutes.deviceList) && r.contains('active=false'),
          ),
          isTrue,
        );
      },
    );

    testWidgets(
      'navigates to device list filtered by profile on profile card tap',
      (WidgetTester tester) async {
        await tester.pumpWidget(buildTestWidget(tester));
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('device-profile-card-prof-1')));
        await tester.pumpAndSettle();

        expect(
          pushedRoutes.any(
            (r) =>
                r.contains(AppRoutes.deviceList) &&
                r.contains('profileId=prof-1'),
          ),
          isTrue,
        );
      },
    );

    testWidgets(
      'touch targets meet >= 48dp minimum for key buttons and pills',
      (WidgetTester tester) async {
        await tester.pumpWidget(buildTestWidget(tester));
        await tester.pumpAndSettle();

        final searchSize = tester.getSize(
          find.byKey(const Key('devices-main-search-button')),
        );
        expect(searchSize.width, greaterThanOrEqualTo(48.0));
        expect(searchSize.height, greaterThanOrEqualTo(48.0));

        final qrSize = tester.getSize(
          find.byKey(const Key('devices-main-qr-button')),
        );
        expect(qrSize.width, greaterThanOrEqualTo(48.0));
        expect(qrSize.height, greaterThanOrEqualTo(48.0));

        final onlineSize = tester.getSize(
          find.byKey(const Key('all-devices-online-pill')),
        );
        expect(onlineSize.height, greaterThanOrEqualTo(48.0));

        final offlineSize = tester.getSize(
          find.byKey(const Key('all-devices-offline-pill')),
        );
        expect(offlineSize.height, greaterThanOrEqualTo(48.0));
      },
    );

    testWidgets(
      'renders cleanly in dark theme and 2.0x text scale with reduced motion',
      (WidgetTester tester) async {
        await tester.pumpWidget(
          buildTestWidget(
            tester,
            theme: tbDarkTheme(),
            textScale: 2.0,
            disableAnimations: true,
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('All devices'), findsOneWidget);
        expect(find.text('Thermometer'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  });
}
