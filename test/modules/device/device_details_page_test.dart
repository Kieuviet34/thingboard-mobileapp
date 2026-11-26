import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:thingsboard_democloud_app/config/routes/router.dart';
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
import 'package:thingsboard_democloud_app/core/models/alarm_models.dart';
import 'package:thingsboard_democloud_app/core/models/asset_models.dart';
import 'package:thingsboard_democloud_app/core/models/device_models.dart';
import 'package:thingsboard_democloud_app/core/models/entity_id.dart';
import 'package:thingsboard_democloud_app/core/models/pagination.dart';
import 'package:thingsboard_democloud_app/core/models/tb_failure.dart';
import 'package:thingsboard_democloud_app/core/models/telemetry_models.dart';
import 'package:thingsboard_democloud_app/modules/device/device_details_page.dart';
import 'package:thingsboard_democloud_app/widgets/tb_empty_state.dart';
import 'package:thingsboard_democloud_app/widgets/tb_section_card.dart';
import 'package:thingsboard_democloud_app/widgets/tb_shimmer.dart';
import 'package:thingsboard_democloud_app/widgets/tb_status_badge.dart';

import '../../helpers/fake_app_preferences.dart';
import '../../helpers/fake_secure_storage.dart';
import '../../helpers/fake_ws_channel.dart';

class _ControlledDeviceDetailsRepo implements DeviceRepository {
  _ControlledDeviceDetailsRepo()
    : device = const TbDeviceInfo(
        id: 'dev-detail-1',
        name: 'Production Chiller A',
        type: 'HVAC Chiller',
        label: 'Facility Plant #2',
        active: true,
        deviceProfileId: 'prof-hvac',
        deviceProfileName: 'Chiller Profile',
        ownerName: 'Acme Corp',
        createdTime: 1700000000000,
        telemetry: {'temperature': '7.4', 'flowRate': '120.5'},
      );

  Completer<TbDeviceInfo>? completer;
  bool shouldThrow = false;
  bool forbiddenCredentials = false;
  TbDeviceInfo device;

  @override
  Future<PageData<TbDeviceProfileSummary>> getDeviceProfiles(
    PageQuery query, {
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
  Future<PageData<TbDeviceInfo>> getDevices(
    PageQuery query,
    TbDeviceQuery filter, {
    CancelToken? cancelToken,
  }) async {
    return PageData(
      data: [device],
      totalPages: 1,
      totalElements: 1,
      hasNext: false,
    );
  }

  @override
  Future<TbDeviceInfo> getDeviceInfo(String deviceId) async {
    if (completer != null) return completer!.future;
    if (shouldThrow) {
      throw const TbFailure(
        type: TbFailureType.networkUnavailable,
        message: 'Could not load device details',
      );
    }
    return device;
  }

  @override
  Future<TbDeviceCredentials> getDeviceCredentials(String deviceId) async {
    if (forbiddenCredentials) {
      throw const TbFailure(
        type: TbFailureType.permissionDenied,
        message: 'Forbidden',
      );
    }
    return TbDeviceCredentials(
      id: 'cred-1',
      deviceId: deviceId,
      credentialsType: 'ACCESS_TOKEN',
      credentialsId: 'token-chiller-xyz-987',
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

class _ControlledTelemetryRepo implements TelemetryRepository {
  final Map<String, List<TbAttributeEntry>> attributesByScope = {
    'SERVER_SCOPE': [
      const TbAttributeEntry(
        key: 'firmwareVersion',
        value: 'v2.4.1',
        lastUpdateTs: 1700000000000,
        scope: TbAttributeScope.serverScope,
      ),
    ],
    'SHARED_SCOPE': [
      const TbAttributeEntry(
        key: 'targetTemp',
        value: 6.5,
        lastUpdateTs: 1700000000000,
        scope: TbAttributeScope.sharedScope,
      ),
    ],
  };

  final List<String> deletedKeys = [];
  final Map<String, dynamic> savedAttributes = {};

  @override
  Future<List<TbAttributeEntry>> getAttributes(
    EntityId entityId,
    TbAttributeScope scope,
  ) async {
    return attributesByScope[scope.wireValue] ?? const [];
  }

  @override
  Future<void> saveAttributes(
    EntityId entityId,
    TbAttributeScope scope,
    Map<String, dynamic> attributes,
  ) async {
    savedAttributes.addAll(attributes);
    final list = attributesByScope.putIfAbsent(scope.wireValue, () => []);
    attributes.forEach((k, v) {
      list.removeWhere((e) => e.key == k);
      list.add(
        TbAttributeEntry(
          key: k,
          value: v,
          lastUpdateTs: 1700000005000,
          scope: scope,
        ),
      );
    });
  }

  @override
  Future<void> deleteAttributes(
    EntityId entityId,
    TbAttributeScope scope,
    List<String> keys,
  ) async {
    deletedKeys.addAll(keys);
    final list = attributesByScope[scope.wireValue];
    if (list != null) {
      list.removeWhere((e) => keys.contains(e.key));
    }
  }

  @override
  Future<Map<String, TbTsPoint>> getLatestTimeseries(
    EntityId entityId, {
    List<String>? keys,
  }) async {
    return {
      'temperature': const TbTsPoint(
        ts: 1700000000000,
        rawValue: 7.4,
        numericValue: 7.4,
      ),
      'flowRate': const TbTsPoint(
        ts: 1700000000000,
        rawValue: 120.5,
        numericValue: 120.5,
      ),
    };
  }

  @override
  Future<Map<String, List<TbTsPoint>>> getTimeseriesHistory(
    TbTsHistoryQuery query, {
    CancelToken? cancelToken,
  }) async {
    return {
      'temperature': [
        const TbTsPoint(ts: 1699990000000, rawValue: 8.0, numericValue: 8.0),
        const TbTsPoint(ts: 1699995000000, rawValue: 7.6, numericValue: 7.6),
        const TbTsPoint(ts: 1700000000000, rawValue: 7.4, numericValue: 7.4),
      ],
      'flowRate': [
        const TbTsPoint(
          ts: 1699990000000,
          rawValue: 115.0,
          numericValue: 115.0,
        ),
        const TbTsPoint(
          ts: 1699995000000,
          rawValue: 118.2,
          numericValue: 118.2,
        ),
        const TbTsPoint(
          ts: 1700000000000,
          rawValue: 120.5,
          numericValue: 120.5,
        ),
      ],
    };
  }
}

class _ControlledRpcRepo implements RpcRepository {
  final List<TbRpcRequest> oneWayCalls = [];
  final List<TbRpcRequest> twoWayCalls = [];

  @override
  Future<Map<String, dynamic>?> sendOneWayRpc(
    String deviceId,
    TbRpcRequest request, {
    CancelToken? cancelToken,
  }) async {
    oneWayCalls.add(request);
    return null;
  }

  @override
  Future<Map<String, dynamic>?> sendTwoWayRpc(
    String deviceId,
    TbRpcRequest request, {
    CancelToken? cancelToken,
  }) async {
    twoWayCalls.add(request);
    return {'result': 'OK', 'status': 'APPLIED'};
  }

  @override
  Future<PageData<TbPersistentRpc>> getPersistentRpcs(
    String deviceId,
    PageQuery query, {
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
  Future<void> deletePersistentRpc(String rpcId) async {}
}

class _ControlledAlarmRepo implements AlarmRepository {
  final List<String> ackCalls = [];
  final List<String> clearCalls = [];

  @override
  Future<PageData<TbAlarmInfo>> getAlarms(
    PageQuery query,
    TbAlarmFilter filter, {
    CancelToken? cancelToken,
  }) async {
    return const PageData(
      data: [
        TbAlarmInfo(
          id: 'alarm-dev-1',
          type: 'High Temp Alert',
          severity: AlarmSeverity.major,
          acknowledged: false,
          cleared: false,
          createdTime: 1700000000000,
          originatorName: 'Production Chiller A',
        ),
      ],
      totalPages: 1,
      totalElements: 1,
      hasNext: false,
    );
  }

  @override
  Future<TbAlarmInfo> getAlarmInfo(String id) async =>
      throw UnimplementedError();

  @override
  Future<TbAlarmInfo> ackAlarm(String id) async {
    ackCalls.add(id);
    return const TbAlarmInfo(
      id: 'alarm-dev-1',
      type: 'High Temp Alert',
      severity: AlarmSeverity.major,
      acknowledged: true,
      cleared: false,
      createdTime: 1700000000000,
    );
  }

  @override
  Future<TbAlarmInfo> clearAlarm(String id) async {
    clearCalls.add(id);
    return const TbAlarmInfo(
      id: 'alarm-dev-1',
      type: 'High Temp Alert',
      severity: AlarmSeverity.major,
      acknowledged: true,
      cleared: true,
      createdTime: 1700000000000,
    );
  }

  @override
  Future<TbAlarmInfo> assignAlarm(String id, String assigneeId) async =>
      throw UnimplementedError();

  @override
  Future<TbAlarmInfo> unassignAlarm(String id) async =>
      throw UnimplementedError();

  @override
  Future<PageData<TbAlarmComment>> getComments(
    String alarmId,
    PageQuery query,
  ) async {
    return const PageData(
      data: [],
      totalPages: 0,
      totalElements: 0,
      hasNext: false,
    );
  }

  @override
  Future<TbAlarmComment> addComment(String alarmId, String text) async =>
      throw UnimplementedError();

  @override
  Future<PageData<TbUserEmailInfo>> getAssignees(
    String alarmId,
    PageQuery query,
  ) async {
    return const PageData(
      data: [],
      totalPages: 0,
      totalElements: 0,
      hasNext: false,
    );
  }
}

class _ControlledAssetRepo implements AssetRepository {
  bool emptyRelations = false;

  @override
  Future<PageData<TbAssetProfileInfo>> getAssetProfiles(PageQuery query) async {
    return const PageData(
      data: [],
      totalPages: 0,
      totalElements: 0,
      hasNext: false,
    );
  }

  @override
  Future<PageData<TbAssetInfo>> getAssets(
    PageQuery query,
    TbAssetQuery filter, {
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
  Future<TbAssetInfo> getAssetInfo(String assetId) async =>
      throw UnimplementedError();

  @override
  Future<List<TbEntityRelationInfo>> getRelations(
    EntityId entity, {
    bool outgoing = true,
  }) async {
    if (emptyRelations) return const [];
    return [
      TbEntityRelationInfo(
        from: entity,
        to: const EntityId(entityType: EntityType.asset, id: 'asset-plant-2'),
        type: 'Contains',
        toName: 'Facility Plant #2',
      ),
    ];
  }
}

void main() {
  late FakeAppPreferences prefs;
  late FakeSecureStorage storage;
  late _ControlledDeviceDetailsRepo deviceRepo;
  late _ControlledTelemetryRepo telemetryRepo;
  late _ControlledRpcRepo rpcRepo;
  late _ControlledAlarmRepo alarmRepo;
  late _ControlledAssetRepo assetRepo;

  setUp(() {
    prefs = FakeAppPreferences();
    storage = FakeSecureStorage();
    deviceRepo = _ControlledDeviceDetailsRepo();
    telemetryRepo = _ControlledTelemetryRepo();
    rpcRepo = _ControlledRpcRepo();
    alarmRepo = _ControlledAlarmRepo();
    assetRepo = _ControlledAssetRepo();
  });

  List<Override> buildOverrides() => [
    tbAppPreferencesProvider.overrideWithValue(prefs),
    tbStorageProvider.overrideWithValue(storage),
    wsChannelFactoryProvider.overrideWithValue((_) => FakeWebSocketChannel()),
    deviceRepositoryProvider.overrideWithValue(deviceRepo),
    telemetryRepositoryProvider.overrideWithValue(telemetryRepo),
    liveEntityTelemetryProvider.overrideWith(
      (ref, arg) => Stream.value(const <String, TbTsPoint>{}),
    ),
    rpcRepositoryProvider.overrideWithValue(rpcRepo),
    alarmRepositoryProvider.overrideWithValue(alarmRepo),
    assetRepositoryProvider.overrideWithValue(assetRepo),
  ];

  Widget buildTestWidget(
    WidgetTester tester, {
    String deviceId = 'dev-detail-1',
    bool embedded = false,
    ThemeData? theme,
    double textScale = 1.0,
    bool disableAnimations = true,
  }) {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    return ProviderScope(
      overrides: buildOverrides(),
      child: MediaQuery(
        data: MediaQueryData(
          size: const Size(800, 1200),
          textScaler: TextScaler.linear(textScale),
          disableAnimations: disableAnimations,
        ),
        child: MaterialApp(
          theme: theme ?? tbLightTheme(),
          home: DeviceDetailsPage(deviceId: deviceId, embedded: embedded),
        ),
      ),
    );
  }

  group('DeviceDetailsPage Widget Tests', () {
    group('Info tab', () {
      final createdText = DateFormat(
        'yyyy-MM-dd HH:mm',
      ).format(DateTime.fromMillisecondsSinceEpoch(1700000000000));

      Future<void> openInfo(WidgetTester tester) async {
        await tester.pumpWidget(buildTestWidget(tester));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Info'));
        await tester.tap(find.text('Info'));
        await tester.pumpAndSettle();
      }

      String textOf(WidgetTester tester, String key) =>
          tester.widget<Text>(find.byKey(Key(key))).data!;

      testWidgets('Overview shows profile name (not type), owner, created', (
        tester,
      ) async {
        await openInfo(tester);

        expect(textOf(tester, 'info-profile-value'), 'Chiller Profile');
        expect(textOf(tester, 'info-label-value'), 'Facility Plant #2');
        expect(textOf(tester, 'info-owner-value'), 'Acme Corp');
        expect(textOf(tester, 'info-created-value'), createdText);
      });

      testWidgets('Overview shows em dash for missing owner and created', (
        tester,
      ) async {
        deviceRepo.device = const TbDeviceInfo(
          id: 'dev-detail-1',
          name: 'Production Chiller A',
          type: 'HVAC Chiller',
          active: true,
        );
        await openInfo(tester);

        expect(textOf(tester, 'info-owner-value'), '—');
        expect(textOf(tester, 'info-created-value'), '—');
        expect(textOf(tester, 'info-label-value'), '—');
        expect(textOf(tester, 'info-profile-value'), 'HVAC Chiller');
      });

      testWidgets('Gateway row shows Yes for bool or string true', (
        tester,
      ) async {
        for (final flag in <Object>[true, 'true']) {
          deviceRepo.device = TbDeviceInfo(
            id: 'dev-detail-1',
            name: 'Production Chiller A',
            type: 'HVAC Chiller',
            active: true,
            additionalInfo: {'gateway': flag},
          );
          await openInfo(tester);

          expect(textOf(tester, 'info-gateway-value'), 'Yes');
          expect(find.text('Gateway'), findsOneWidget);
          await tester.pumpWidget(const SizedBox());
        }
      });

      testWidgets('Gateway row is hidden when absent or false', (tester) async {
        for (final info in <Map<String, dynamic>>[
          const {},
          const {'gateway': false},
          const {'gateway': 'false'},
        ]) {
          deviceRepo.device = TbDeviceInfo(
            id: 'dev-detail-1',
            name: 'Production Chiller A',
            type: 'HVAC Chiller',
            active: true,
            additionalInfo: info,
          );
          await openInfo(tester);

          expect(find.text('Gateway'), findsNothing);
          expect(find.byKey(const Key('info-gateway-value')), findsNothing);
          await tester.pumpWidget(const SizedBox());
        }
      });

      testWidgets('status badge shows ONLINE when active', (tester) async {
        await openInfo(tester);

        expect(
          find.descendant(
            of: find.byKey(const Key('info-status-badge')),
            matching: find.text('ONLINE'),
          ),
          findsOneWidget,
        );
      });

      testWidgets('status badge shows OFFLINE when inactive', (tester) async {
        deviceRepo.device = deviceRepo.device.copyWith(active: false);
        await openInfo(tester);

        expect(
          find.descendant(
            of: find.byKey(const Key('info-status-badge')),
            matching: find.text('OFFLINE'),
          ),
          findsOneWidget,
        );
      });

      testWidgets(
        'uses three TbSectionCards: Overview, Credentials, Relations',
        (tester) async {
          await openInfo(tester);

          expect(find.byType(TbSectionCard), findsNWidgets(3));
          for (final title in ['Overview', 'Credentials', 'Relations']) {
            expect(find.text(title), findsOneWidget);
          }
        },
      );

      testWidgets('credentials Show, Copy and Hide work', (tester) async {
        String? clipboard;
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          (call) async {
            if (call.method == 'Clipboard.setData') {
              clipboard =
                  (call.arguments as Map<dynamic, dynamic>)['text'] as String?;
            }
            return null;
          },
        );
        addTearDown(
          () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            SystemChannels.platform,
            null,
          ),
        );
        await openInfo(tester);

        expect(find.byKey(const Key('credentials-id-text')), findsNothing);
        await tester.tap(find.byKey(const Key('toggle-credentials-button')));
        await tester.pumpAndSettle();
        expect(find.text('token-chiller-xyz-987'), findsOneWidget);

        await tester.tap(find.byTooltip('Copy credentials'));
        await tester.pumpAndSettle();
        expect(clipboard, 'token-chiller-xyz-987');
        expect(find.text('Credentials copied'), findsOneWidget);

        await tester.tap(find.byKey(const Key('toggle-credentials-button')));
        await tester.pumpAndSettle();
        expect(find.text('Show'), findsOneWidget);
        expect(find.byKey(const Key('credentials-id-text')), findsNothing);
      });

      testWidgets('empty relations show No linked entities', (tester) async {
        assetRepo.emptyRelations = true;
        await openInfo(tester);

        expect(find.text('No linked entities'), findsOneWidget);
      });

      testWidgets('relation tap navigates to the linked entity', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(800, 1200);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });
        final router = GoRouter(
          routes: [
            GoRoute(
              path: '/',
              builder: (_, _) =>
                  const DeviceDetailsPage(deviceId: 'dev-detail-1'),
            ),
            GoRoute(
              path: AppRoutes.assetDetails,
              builder: (_, state) =>
                  Text('asset-route-${state.pathParameters['id']}'),
            ),
          ],
        );
        addTearDown(router.dispose);

        await tester.pumpWidget(
          ProviderScope(
            overrides: buildOverrides(),
            child: MediaQuery(
              data: const MediaQueryData(
                size: Size(800, 1200),
                disableAnimations: true,
              ),
              child: MaterialApp.router(
                theme: tbLightTheme(),
                routerConfig: router,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Info'));
        await tester.tap(find.text('Info'));
        await tester.pumpAndSettle();

        final tile = find.byKey(const Key('relation-asset-plant-2'));
        await tester.ensureVisible(tile);
        await tester.tap(tile);
        await tester.pumpAndSettle();

        expect(find.text('asset-route-asset-plant-2'), findsOneWidget);
      });
    });

    testWidgets('renders shimmer loader when fetching device info', (
      WidgetTester tester,
    ) async {
      deviceRepo.completer = Completer<TbDeviceInfo>();

      await tester.pumpWidget(buildTestWidget(tester));
      await tester.pump();

      expect(find.byType(TbShimmerList), findsWidgets);
    });

    testWidgets('renders error state and retries successfully', (
      WidgetTester tester,
    ) async {
      deviceRepo.shouldThrow = true;

      await tester.pumpWidget(buildTestWidget(tester));
      await tester.pumpAndSettle();

      expect(find.byType(TbEmptyState), findsOneWidget);
      expect(find.text('Failed to load device'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);

      deviceRepo.shouldThrow = false;
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();

      expect(find.text('Production Chiller A'), findsWidgets);
    });

    testWidgets(
      'renders device header with custom icon, status badge, and 5-section segmented button',
      (WidgetTester tester) async {
        await tester.pumpWidget(buildTestWidget(tester));
        await tester.pumpAndSettle();

        expect(find.text('Production Chiller A'), findsWidgets);
        expect(find.text('HVAC Chiller · Facility Plant #2'), findsOneWidget);
        expect(find.byType(TbStatusBadge), findsWidgets);
        expect(find.text('ONLINE'), findsOneWidget);

        expect(
          find.byKey(const Key('device-section-segmented')),
          findsOneWidget,
        );
        expect(find.text('Telemetry'), findsOneWidget);
        expect(find.text('Attributes'), findsOneWidget);
        expect(find.text('RPC'), findsOneWidget);
        expect(find.text('Alarms'), findsOneWidget);
        expect(find.text('Info'), findsOneWidget);
      },
    );

    testWidgets(
      'renders telemetry section with metric cards, sparkline charts, and switches time windows',
      (WidgetTester tester) async {
        await tester.pumpWidget(buildTestWidget(tester));
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('sparkline-card-temperature')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('sparkline-card-flowRate')),
          findsOneWidget,
        );

        expect(find.byKey(const Key('telemetry-window-1h')), findsOneWidget);
        expect(find.byKey(const Key('telemetry-window-24h')), findsOneWidget);
        expect(find.byKey(const Key('telemetry-window-7d')), findsOneWidget);

        await tester.tap(find.byKey(const Key('telemetry-window-7d')));
        await tester.pumpAndSettle();

        expect(find.text('Production Chiller A'), findsWidgets);
      },
    );

    testWidgets(
      'renders attributes section, filters scope, and adds a new attribute via bottom sheet',
      (WidgetTester tester) async {
        await tester.pumpWidget(buildTestWidget(tester));
        await tester.pumpAndSettle();

        final attrTab = find.text('Attributes');
        await tester.ensureVisible(attrTab);
        await tester.tap(attrTab);
        await tester.pumpAndSettle();

        expect(find.text('Server'), findsOneWidget);
        expect(find.text('Shared'), findsOneWidget);
        expect(find.text('firmwareVersion'), findsOneWidget);
        expect(find.text('v2.4.1'), findsOneWidget);

        // Add attribute button
        expect(find.byKey(const Key('attr-add-button')), findsOneWidget);
        await tester.tap(find.byKey(const Key('attr-add-button')));
        await tester.pumpAndSettle();

        await tester.enterText(
          find.byKey(const Key('attr-key-input')),
          'maxPower',
        );
        await tester.enterText(
          find.byKey(const Key('attr-value-input')),
          '45.0',
        );
        await tester.tap(find.byKey(const Key('attr-save-button')));
        await tester.pumpAndSettle();

        expect(telemetryRepo.savedAttributes, containsPair('maxPower', 45.0));
        expect(find.text('Saved maxPower'), findsOneWidget);
      },
    );

    testWidgets('deletes an attribute in attributes section', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(buildTestWidget(tester));
      await tester.pumpAndSettle();

      final attrTab = find.text('Attributes');
      await tester.ensureVisible(attrTab);
      await tester.tap(attrTab);
      await tester.pumpAndSettle();

      expect(find.text('firmwareVersion'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.delete_outline));
      await tester.pumpAndSettle();

      expect(telemetryRepo.deletedKeys, contains('firmwareVersion'));
      expect(find.text('Deleted firmwareVersion'), findsOneWidget);
    });

    testWidgets(
      'renders RPC section, switches to one-way, fills form, and submits RPC command',
      (WidgetTester tester) async {
        await tester.pumpWidget(buildTestWidget(tester));
        await tester.pumpAndSettle();

        final rpcTab = find.text('RPC');
        await tester.ensureVisible(rpcTab);
        await tester.tap(rpcTab);
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('rpc-mode-segmented')), findsOneWidget);
        expect(find.byKey(const Key('rpc-method-input')), findsOneWidget);
        expect(find.byKey(const Key('rpc-params-input')), findsOneWidget);
        expect(find.byKey(const Key('rpc-send-button')), findsOneWidget);

        // Switch to one-way
        final oneWaySegment = find.text('One-way');
        await tester.ensureVisible(oneWaySegment);
        await tester.tap(oneWaySegment);
        await tester.pumpAndSettle();

        await tester.enterText(
          find.byKey(const Key('rpc-method-input')),
          'setSpeed',
        );
        await tester.enterText(
          find.byKey(const Key('rpc-params-input')),
          '{"rpm": 1800}',
        );
        await tester.tap(find.byKey(const Key('rpc-send-button')));
        await tester.pumpAndSettle();

        expect(rpcRepo.oneWayCalls.any((c) => c.method == 'setSpeed'), isTrue);
      },
    );

    testWidgets(
      'renders device alarms section with quick Ack and Clear actions',
      (WidgetTester tester) async {
        await tester.pumpWidget(buildTestWidget(tester));
        await tester.pumpAndSettle();

        final alarmsTab = find.text('Alarms');
        await tester.ensureVisible(alarmsTab);
        await tester.tap(alarmsTab);
        await tester.pumpAndSettle();

        expect(find.text('High Temp Alert'), findsOneWidget);
        expect(find.text('MAJOR'), findsOneWidget);

        expect(
          find.byKey(const Key('device-alarm-ack-alarm-dev-1')),
          findsOneWidget,
        );
        await tester.tap(find.byKey(const Key('device-alarm-ack-alarm-dev-1')));
        await tester.pumpAndSettle();

        expect(alarmRepo.ackCalls, contains('alarm-dev-1'));

        expect(
          find.byKey(const Key('device-alarm-clear-alarm-dev-1')),
          findsOneWidget,
        );
        await tester.tap(
          find.byKey(const Key('device-alarm-clear-alarm-dev-1')),
        );
        await tester.pumpAndSettle();

        expect(alarmRepo.clearCalls, contains('alarm-dev-1'));
      },
    );

    testWidgets(
      'renders info section metadata and toggles credentials display',
      (WidgetTester tester) async {
        await tester.pumpWidget(buildTestWidget(tester));
        await tester.pumpAndSettle();

        final infoTab = find.text('Info');
        await tester.ensureVisible(infoTab);
        await tester.tap(infoTab);
        await tester.pumpAndSettle();

        expect(find.text('Facility Plant #2'), findsWidgets);
        expect(find.text('Credentials'), findsOneWidget);

        expect(
          find.byKey(const Key('toggle-credentials-button')),
          findsOneWidget,
        );
        expect(find.text('Show'), findsOneWidget);

        await tester.tap(find.byKey(const Key('toggle-credentials-button')));
        await tester.pumpAndSettle();

        expect(find.text('Hide'), findsOneWidget);
        expect(find.text('ACCESS_TOKEN'), findsOneWidget);
        expect(find.text('token-chiller-xyz-987'), findsOneWidget);
      },
    );

    testWidgets(
      'renders 403 permission denied notice safely when credentials access restricted',
      (WidgetTester tester) async {
        deviceRepo.forbiddenCredentials = true;

        await tester.pumpWidget(buildTestWidget(tester));
        await tester.pumpAndSettle();

        final infoTab = find.text('Info');
        await tester.ensureVisible(infoTab);
        await tester.tap(infoTab);
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('toggle-credentials-button')));
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('credentials-error-notice')),
          findsOneWidget,
        );
        expect(
          find.text('Restricted — insufficient permissions'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'renders embedded mode with refresh action and no top navigation bar',
      (WidgetTester tester) async {
        await tester.pumpWidget(buildTestWidget(tester, embedded: true));
        await tester.pumpAndSettle();

        expect(find.byTooltip('Refresh device'), findsOneWidget);
        expect(find.byTooltip('Back'), findsNothing);
      },
    );

    testWidgets('key action touch targets meet >= 48dp minimum', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(buildTestWidget(tester));
      await tester.pumpAndSettle();

      final alarmsTab = find.text('Alarms');
      await tester.ensureVisible(alarmsTab);
      await tester.tap(alarmsTab);
      await tester.pumpAndSettle();

      final ackTarget = tester.getSize(
        find.byKey(const Key('device-alarm-ack-alarm-dev-1')),
      );
      expect(ackTarget.width, greaterThanOrEqualTo(48.0));
      expect(ackTarget.height, greaterThanOrEqualTo(48.0));

      final clearTarget = tester.getSize(
        find.byKey(const Key('device-alarm-clear-alarm-dev-1')),
      );
      expect(clearTarget.width, greaterThanOrEqualTo(48.0));
      expect(clearTarget.height, greaterThanOrEqualTo(48.0));
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

        expect(find.text('Production Chiller A'), findsWidgets);
        expect(tester.takeException(), isNull);
      },
    );
  });
}
