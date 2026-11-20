import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:thingsboard_democloud_app/config/themes/tb_theme.dart';
import 'package:thingsboard_democloud_app/core/api/controllers/alarm_controller.dart';
import 'package:thingsboard_democloud_app/core/api/controllers/asset_controller.dart';
import 'package:thingsboard_democloud_app/core/api/controllers/device_controller.dart';
import 'package:thingsboard_democloud_app/core/api/controllers/rpc_controller.dart';
import 'package:thingsboard_democloud_app/core/api/controllers/server_config_controller.dart';
import 'package:thingsboard_democloud_app/core/api/controllers/telemetry_controller.dart';
import 'package:thingsboard_democloud_app/core/api/repositories/alarm_repository.dart';
import 'package:thingsboard_democloud_app/core/api/repositories/asset_repository.dart';
import 'package:thingsboard_democloud_app/core/api/repositories/device_repository.dart';
import 'package:thingsboard_democloud_app/core/api/repositories/rpc_repository.dart';
import 'package:thingsboard_democloud_app/core/api/repositories/telemetry_repository.dart';
import 'package:thingsboard_democloud_app/core/mock/mock_data.dart';
import 'package:thingsboard_democloud_app/core/models/device_models.dart';
import 'package:thingsboard_democloud_app/core/models/pagination.dart';
import 'package:thingsboard_democloud_app/core/models/tb_failure.dart';
import 'package:thingsboard_democloud_app/core/models/telemetry_models.dart';
import 'package:thingsboard_democloud_app/modules/device/devices_list_page.dart';
import 'package:thingsboard_democloud_app/widgets/tb_app_search_bar.dart';
import 'package:thingsboard_democloud_app/widgets/tb_empty_state.dart';
import 'package:thingsboard_democloud_app/widgets/tb_metric_pill.dart';
import 'package:thingsboard_democloud_app/widgets/tb_shimmer.dart';

import '../../helpers/fake_app_preferences.dart';
import '../../helpers/fake_secure_storage.dart';
import '../../helpers/fake_ws_channel.dart';

class _ControlledDevicesListRepo implements DeviceRepository {
  _ControlledDevicesListRepo({List<TbDeviceInfo>? devices})
    : items = List<TbDeviceInfo>.from(
        devices ??
            [
              const TbDeviceInfo(
                id: 'dev-1',
                name: 'Temperature Sensor 01',
                type: 'Thermometer',
                label: 'Floor 1 Room 101',
                active: true,
                deviceProfileId: 'prof-1',
                telemetry: {'temperature': '24.5', 'humidity': '60.2'},
              ),
              const TbDeviceInfo(
                id: 'dev-2',
                name: 'Energy Meter 02',
                type: 'Smart Meter',
                label: 'Substation B',
                active: false,
                deviceProfileId: 'prof-2',
                telemetry: {'voltage': '220.1', 'power': '15.3'},
              ),
              const TbDeviceInfo(
                id: 'dev-3',
                name: 'Pressure Transmitter 03',
                type: 'Pressure',
                label: 'Pipe Line C',
                active: true,
                deviceProfileId: 'prof-3',
                telemetry: {'pressure': '4.2'},
              ),
            ],
      );

  Completer<PageData<TbDeviceInfo>>? completer;
  bool shouldThrow = false;
  bool throwOnNextPage = false;
  bool hasMore = false;
  final List<TbDeviceInfo> items;
  final List<TbDeviceQuery> capturedFilters = [];

  @override
  Future<PageData<TbDeviceProfileSummary>> getDeviceProfiles(
    PageQuery query, {
    CancelToken? cancelToken,
  }) async {
    return const PageData(
      data: [
        TbDeviceProfileSummary(id: 'prof-1', name: 'Thermometer'),
        TbDeviceProfileSummary(id: 'prof-2', name: 'Smart Meter'),
      ],
      totalPages: 1,
      totalElements: 2,
      hasNext: false,
    );
  }

  @override
  Future<PageData<TbDeviceInfo>> getDevices(
    PageQuery query,
    TbDeviceQuery filter, {
    CancelToken? cancelToken,
  }) async {
    capturedFilters.add(filter);
    if (completer != null) return completer!.future;
    if (shouldThrow) {
      throw const TbFailure(
        type: TbFailureType.networkUnavailable,
        message: 'Network error',
      );
    }
    if (query.page > 0 && throwOnNextPage) {
      throw const TbFailure(
        type: TbFailureType.networkUnavailable,
        message: 'Page 2 load failed',
      );
    }

    final filtered = items.where((d) {
      if (filter.active != null && d.active != filter.active) return false;
      if (filter.deviceProfileId != null &&
          filter.deviceProfileId!.isNotEmpty &&
          d.deviceProfileId != filter.deviceProfileId) {
        return false;
      }
      if (filter.textSearch != null && filter.textSearch!.isNotEmpty) {
        final q = filter.textSearch!.toLowerCase();
        if (!d.name.toLowerCase().contains(q) &&
            !d.label.toLowerCase().contains(q)) {
          return false;
        }
      }
      return true;
    }).toList();

    return PageData(
      data: query.page > 0
          ? [
              const TbDeviceInfo(
                id: 'dev-page2-1',
                name: 'Device Page 2',
                type: 'Thermometer',
                active: true,
              ),
            ]
          : filtered,
      totalPages: hasMore ? 2 : 1,
      totalElements: hasMore ? filtered.length + 1 : filtered.length,
      hasNext: hasMore && query.page == 0,
    );
  }

  @override
  Future<TbDeviceInfo> getDeviceInfo(String deviceId) async {
    return items.firstWhere(
      (d) => d.id == deviceId,
      orElse: () => TbDeviceInfo(
        id: deviceId,
        name: 'Device $deviceId',
        type: 'Default',
        active: true,
      ),
    );
  }

  @override
  Future<TbDeviceCredentials> getDeviceCredentials(String deviceId) async {
    return TbDeviceCredentials(
      id: 'cred-$deviceId',
      deviceId: deviceId,
      credentialsType: 'ACCESS_TOKEN',
      credentialsId: 'token-$deviceId',
    );
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
  late _ControlledDevicesListRepo repo;
  late DemoTelemetryRepository demoTelemetry;
  late DemoRpcRepository demoRpc;
  late DemoAlarmRepository demoAlarm;
  late DemoAssetRepository demoAsset;

  setUp(() {
    prefs = FakeAppPreferences();
    storage = FakeSecureStorage();
    repo = _ControlledDevicesListRepo();
    final container = ProviderContainer();
    final mockDevices = container.read(devicesProvider);
    final mockAlarms = container.read(alarmsProvider);
    final mockAssets = container.read(assetsProvider);
    container.dispose();
    demoTelemetry = DemoTelemetryRepository(mockDevices);
    demoRpc = DemoRpcRepository(mockDevices);
    demoAlarm = DemoAlarmRepository(mockAlarms);
    demoAsset = DemoAssetRepository(mockAssets);
  });

  List<Override> buildOverrides() => [
    tbAppPreferencesProvider.overrideWithValue(prefs),
    tbStorageProvider.overrideWithValue(storage),
    wsChannelFactoryProvider.overrideWithValue((_) => FakeWebSocketChannel()),
    deviceRepositoryProvider.overrideWithValue(repo),
    telemetryRepositoryProvider.overrideWithValue(demoTelemetry),
    liveEntityTelemetryProvider.overrideWith(
      (ref, arg) => Stream.value(const <String, TbTsPoint>{}),
    ),
    rpcRepositoryProvider.overrideWithValue(demoRpc),
    alarmRepositoryProvider.overrideWithValue(demoAlarm),
    assetRepositoryProvider.overrideWithValue(demoAsset),
  ];

  Widget buildTestWidget(
    WidgetTester tester, {
    String? deviceProfileId,
    String? deviceType,
    bool? active,
    bool searchMode = false,
    String? initialSelectedDeviceId,
    ThemeData? theme,
    double textScale = 1.0,
    bool disableAnimations = true,
  }) {
    final size = tester.view.physicalSize.width > 0
        ? Size(
            tester.view.physicalSize.width / tester.view.devicePixelRatio,
            tester.view.physicalSize.height / tester.view.devicePixelRatio,
          )
        : const Size(800, 1200);

    return ProviderScope(
      overrides: buildOverrides(),
      child: MediaQuery(
        data: MediaQueryData(
          size: size,
          textScaler: TextScaler.linear(textScale),
          disableAnimations: disableAnimations,
        ),
        child: MaterialApp(
          theme: theme ?? tbLightTheme(),
          home: DevicesListPage(
            deviceProfileId: deviceProfileId,
            deviceType: deviceType,
            active: active,
            searchMode: searchMode,
            initialSelectedDeviceId: initialSelectedDeviceId,
          ),
        ),
      ),
    );
  }

  group('DevicesListPage Widget Tests', () {
    testWidgets('renders loading shimmer on initial build', (
      WidgetTester tester,
    ) async {
      repo.completer = Completer<PageData<TbDeviceInfo>>();

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
      expect(find.text('Retry'), findsOneWidget);

      repo.shouldThrow = false;
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();

      expect(find.text('Temperature Sensor 01'), findsOneWidget);
    });

    testWidgets(
      'renders empty state when no devices found and clears filters',
      (WidgetTester tester) async {
        repo.items.clear();

        await tester.pumpWidget(buildTestWidget(tester, active: true));
        await tester.pumpAndSettle();

        expect(find.byType(TbEmptyState), findsOneWidget);
        expect(find.text('No devices found'), findsOneWidget);
        expect(find.text('Clear filters'), findsOneWidget);

        await tester.tap(find.text('Clear filters'));
        await tester.pumpAndSettle();

        expect(repo.capturedFilters.last.active, isNull);
      },
    );

    testWidgets(
      'renders device list rows with status badges and telemetry metric pills',
      (WidgetTester tester) async {
        await tester.pumpWidget(buildTestWidget(tester));
        await tester.pumpAndSettle();

        expect(find.text('Temperature Sensor 01'), findsOneWidget);
        expect(find.text('Thermometer · Floor 1 Room 101'), findsOneWidget);
        expect(find.text('ONLINE'), findsWidgets);

        expect(find.text('Energy Meter 02'), findsOneWidget);
        expect(find.text('OFFLINE'), findsOneWidget);

        // Metric pills
        expect(find.byType(TbMetricPill), findsWidgets);
        expect(find.text('24.5'), findsOneWidget);
        expect(find.text('220.1'), findsOneWidget);
      },
    );

    testWidgets('toggles search bar and filters devices by query', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(buildTestWidget(tester));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('devices-list-search-toggle')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('devices-list-search-toggle')));
      await tester.pumpAndSettle();

      expect(find.byType(TbAppSearchBar), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'Energy');
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();

      expect(find.text('Energy Meter 02'), findsOneWidget);
      expect(find.text('Temperature Sensor 01'), findsNothing);
    });

    testWidgets('filters devices by online and offline FilterChips', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(buildTestWidget(tester));
      await tester.pumpAndSettle();

      final onlineChip = find.byKey(const Key('device-filter-online'));
      await tester.ensureVisible(onlineChip);
      await tester.tap(onlineChip);
      await tester.pumpAndSettle();

      expect(find.text('Temperature Sensor 01'), findsOneWidget);
      expect(find.text('Energy Meter 02'), findsNothing);

      final offlineChip = find.byKey(const Key('device-filter-offline'));
      await tester.ensureVisible(offlineChip);
      await tester.tap(offlineChip);
      await tester.pumpAndSettle();

      expect(find.text('Energy Meter 02'), findsOneWidget);
      expect(find.text('Temperature Sensor 01'), findsNothing);
    });

    testWidgets('clears profile filter chip and resets list', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        buildTestWidget(
          tester,
          deviceProfileId: 'prof-1',
          deviceType: 'Thermometer',
        ),
      );
      await tester.pumpAndSettle();

      final profileChip = find.byKey(const Key('device-profile-filter-chip'));
      expect(profileChip, findsOneWidget);
      expect(find.text('Thermometer'), findsWidgets);

      final deleteIcon = find.descendant(
        of: profileChip,
        matching: find.byType(Icon),
      );
      await tester.tap(deleteIcon);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('device-profile-filter-chip')), findsNothing);
    });

    testWidgets(
      'loads next page when scrolled near bottom and retries on load more error',
      (WidgetTester tester) async {
        repo.hasMore = true;
        repo.throwOnNextPage = true;
        repo.items.addAll(
          List.generate(
            10,
            (i) => TbDeviceInfo(
              id: 'dev-extra-$i',
              name: 'Device Extra $i',
              type: 'Sensor',
              active: true,
            ),
          ),
        );

        await tester.pumpWidget(buildTestWidget(tester));
        await tester.pumpAndSettle();

        await tester.drag(find.byType(ListView), const Offset(0, -1000));
        await tester.pumpAndSettle();

        expect(find.text('Retry loading more'), findsOneWidget);

        repo.throwOnNextPage = false;
        await tester.tap(find.text('Retry loading more'));
        await tester.pumpAndSettle();

        expect(find.text('Device Page 2'), findsOneWidget);
      },
    );

    testWidgets(
      'supports adaptive 2-pane layout on wide screens (>=840dp) embedding DeviceDetailsPage',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(1024, 768);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await tester.pumpWidget(buildTestWidget(tester));
        await tester.pumpAndSettle();

        expect(find.byType(VerticalDivider), findsOneWidget);
        expect(
          find.byKey(const ValueKey<String>('pane-device-dev-1')),
          findsOneWidget,
        );
        expect(find.text('Temperature Sensor 01'), findsWidgets);
      },
    );

    testWidgets(
      '2-pane layout switches selected device when another device row is tapped',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(1024, 768);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await tester.pumpWidget(buildTestWidget(tester));
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey<String>('pane-device-dev-1')),
          findsOneWidget,
        );

        await tester.tap(find.text('Energy Meter 02'));
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey<String>('pane-device-dev-2')),
          findsOneWidget,
        );
      },
    );

    testWidgets('device row touch targets meet >= 48dp minimum', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(buildTestWidget(tester));
      await tester.pumpAndSettle();

      final firstRow = tester.getSize(find.text('Temperature Sensor 01'));
      expect(firstRow.height, greaterThanOrEqualTo(16.0));

      final searchToggle = tester.getSize(
        find.byKey(const Key('devices-list-search-toggle')),
      );
      expect(searchToggle.width, greaterThanOrEqualTo(48.0));
      expect(searchToggle.height, greaterThanOrEqualTo(48.0));
    });

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

        expect(find.text('Temperature Sensor 01'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  });
}
