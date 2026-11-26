import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:thingsboard_democloud_app/config/themes/tb_theme.dart';
import 'package:thingsboard_democloud_app/core/api/controllers/alarm_controller.dart';
import 'package:thingsboard_democloud_app/core/api/controllers/asset_controller.dart';
import 'package:thingsboard_democloud_app/core/api/controllers/server_config_controller.dart';
import 'package:thingsboard_democloud_app/core/api/controllers/telemetry_controller.dart';
import 'package:thingsboard_democloud_app/core/api/repositories/alarm_repository.dart';
import 'package:thingsboard_democloud_app/core/api/repositories/asset_repository.dart';
import 'package:thingsboard_democloud_app/core/api/repositories/telemetry_repository.dart';
import 'package:thingsboard_democloud_app/core/models/alarm_models.dart';
import 'package:thingsboard_democloud_app/core/models/asset_models.dart';
import 'package:thingsboard_democloud_app/core/models/entity_id.dart';
import 'package:thingsboard_democloud_app/core/models/pagination.dart';
import 'package:thingsboard_democloud_app/core/models/tb_failure.dart';
import 'package:thingsboard_democloud_app/core/models/telemetry_models.dart';
import 'package:thingsboard_democloud_app/modules/asset/asset_details_page.dart';
import 'package:thingsboard_democloud_app/widgets/tb_empty_state.dart';
import 'package:thingsboard_democloud_app/widgets/tb_motion.dart';
import 'package:thingsboard_democloud_app/widgets/tb_section_card.dart';
import 'package:thingsboard_democloud_app/widgets/tb_status_badge.dart';

import '../../helpers/fake_app_preferences.dart';
import '../../helpers/fake_secure_storage.dart';
import '../../helpers/fake_ws_channel.dart';
import '../../helpers/mock_dio_adapter.dart';

class _FakeAssetRepo implements AssetRepository {
  _FakeAssetRepo({this.throwFailure});

  final TbAssetInfo asset = const TbAssetInfo(
    id: 'asset-1',
    name: 'Central Solar Farm',
    type: 'Facility',
    ownerName: 'Green Power LLC',
  );
  final List<TbEntityRelationInfo> relations = const [
    TbEntityRelationInfo(
      from: EntityId(entityType: EntityType.asset, id: 'asset-1'),
      to: EntityId(entityType: EntityType.device, id: 'dev-1'),
      type: 'Contains',
      toName: 'Solar Inverter 01',
    ),
  ];
  final TbFailure? throwFailure;

  @override
  Future<PageData<TbAssetInfo>> getAssets(
    PageQuery query,
    TbAssetQuery filter, {
    CancelToken? cancelToken,
  }) async =>
      PageData(data: [asset], totalPages: 1, totalElements: 1, hasNext: false);

  @override
  Future<TbAssetInfo> getAssetInfo(String assetId) async {
    if (throwFailure != null) throw throwFailure!;
    return asset;
  }

  @override
  Future<PageData<TbAssetProfileInfo>> getAssetProfiles(
    PageQuery query,
  ) async =>
      const PageData(data: [], totalPages: 1, totalElements: 0, hasNext: false);

  @override
  Future<List<TbEntityRelationInfo>> getRelations(
    EntityId entity, {
    bool outgoing = true,
  }) async => relations;
}

class _FakeTelemetryRepo implements TelemetryRepository {
  @override
  Future<List<TbAttributeEntry>> getAttributes(
    EntityId entityId,
    TbAttributeScope scope,
  ) async => [
    const TbAttributeEntry(
      key: 'activeAlerts',
      value: '0',
      lastUpdateTs: 1000,
      scope: TbAttributeScope.serverScope,
    ),
  ];

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
  }) async => {
    'temperature': const TbTsPoint(
      ts: 1000,
      rawValue: 24.5,
      numericValue: 24.5,
    ),
  };

  @override
  Future<Map<String, List<TbTsPoint>>> getTimeseriesHistory(
    TbTsHistoryQuery query, {
    CancelToken? cancelToken,
  }) async => {
    'temperature': [
      const TbTsPoint(ts: 1000, rawValue: 24.0, numericValue: 24.0),
      const TbTsPoint(ts: 2000, rawValue: 25.0, numericValue: 25.0),
    ],
  };
}

class _FakeAlarmRepo implements AlarmRepository {
  @override
  Future<PageData<TbAlarmInfo>> getAlarms(
    PageQuery query,
    TbAlarmFilter filter, {
    CancelToken? cancelToken,
  }) async => PageData(
    data: [
      const TbAlarmInfo(
        id: 'alm-1',
        type: 'High Inverter Temperature',
        severity: AlarmSeverity.warning,
        acknowledged: false,
        cleared: false,
        createdTime: 1700000000000,
      ),
    ],
    totalPages: 1,
    totalElements: 1,
    hasNext: false,
  );

  @override
  Future<TbAlarmInfo> getAlarmInfo(String alarmId) async =>
      throw UnimplementedError();

  @override
  Future<TbAlarmInfo> ackAlarm(String alarmId) async => const TbAlarmInfo(
    id: 'alm-1',
    type: 'High Inverter Temperature',
    severity: AlarmSeverity.warning,
    acknowledged: true,
    cleared: false,
    createdTime: 1700000000000,
  );

  @override
  Future<TbAlarmInfo> clearAlarm(String alarmId) async => const TbAlarmInfo(
    id: 'alm-1',
    type: 'High Inverter Temperature',
    severity: AlarmSeverity.warning,
    acknowledged: true,
    cleared: true,
    createdTime: 1700000000000,
  );

  @override
  Future<TbAlarmInfo> assignAlarm(String alarmId, String assigneeId) async =>
      throw UnimplementedError();

  @override
  Future<TbAlarmInfo> unassignAlarm(String alarmId) async =>
      throw UnimplementedError();

  @override
  Future<PageData<TbUserEmailInfo>> getAssignees(
    String alarmId,
    PageQuery query,
  ) async =>
      const PageData(data: [], totalPages: 1, totalElements: 0, hasNext: false);

  @override
  Future<PageData<TbAlarmComment>> getComments(
    String alarmId,
    PageQuery query,
  ) async =>
      const PageData(data: [], totalPages: 1, totalElements: 0, hasNext: false);

  @override
  Future<TbAlarmComment> addComment(String alarmId, String text) async =>
      throw UnimplementedError();
}

void main() {
  Widget buildApp({
    AssetRepository? assetRepo,
    TelemetryRepository? telemetryRepo,
    AlarmRepository? alarmRepo,
    String assetId = 'asset-1',
    bool embedded = false,
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
        assetRepositoryProvider.overrideWithValue(
          assetRepo ?? _FakeAssetRepo(),
        ),
        telemetryRepositoryProvider.overrideWithValue(
          telemetryRepo ?? _FakeTelemetryRepo(),
        ),
        alarmRepositoryProvider.overrideWithValue(
          alarmRepo ?? _FakeAlarmRepo(),
        ),
      ],
      child: MediaQuery(
        data: MediaQueryData(
          size: const Size(390, 844),
          textScaler: TextScaler.linear(textScale),
          disableAnimations: disableAnimations,
        ),
        child: MaterialApp(
          theme: theme ?? tbLightTheme(),
          home: AssetDetailsPage(assetId: assetId, embedded: embedded),
        ),
      ),
    );
  }

  group('AssetDetailsPage', () {
    testWidgets('uses TbSectionCard sections with TbKvRow details', (
      tester,
    ) async {
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      expect(find.widgetWithText(TbSectionCard, 'Details'), findsOneWidget);
      expect(find.widgetWithText(TbKvRow, 'Type'), findsOneWidget);
      expect(find.widgetWithText(TbKvRow, 'Owner'), findsOneWidget);
      expect(find.text('Latest'), findsOneWidget);
      expect(find.text('History (24 Hours)'), findsOneWidget);

      await tester.tap(find.text('Attributes'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(TbSectionCard, 'Attributes'), findsOneWidget);
      expect(find.widgetWithText(TbKvRow, 'activeAlerts'), findsOneWidget);

      await tester.tap(find.text('Alarms'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(TbSectionCard, 'Alarms'), findsOneWidget);

      await tester.tap(find.text('Relations'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(TbSectionCard, 'Relations'), findsOneWidget);
    });

    testWidgets(
      'renders header and switches between Telemetry, Attributes, Alarms, and Relations tabs',
      (tester) async {
        await tester.pumpWidget(buildApp());
        await tester.pumpAndSettle();

        // Header check
        expect(find.text('Central Solar Farm'), findsWidgets);
        expect(find.text('Facility'), findsOneWidget);
        expect(find.text('Green Power LLC'), findsOneWidget);

        // Telemetry tab (default)
        expect(find.text('temperature'), findsWidgets);
        expect(find.text('24.5'), findsOneWidget);
        expect(find.byType(TbSparklineChart), findsOneWidget);

        // Switch to Attributes tab
        await tester.tap(find.text('Attributes'));
        await tester.pumpAndSettle();
        expect(find.text('activeAlerts'), findsOneWidget);
        expect(find.text('0'), findsOneWidget);

        // Switch to Alarms tab
        await tester.tap(find.text('Alarms'));
        await tester.pumpAndSettle();
        expect(find.text('High Inverter Temperature'), findsOneWidget);
        expect(find.byType(TbStatusBadge), findsWidgets);
        expect(find.text('Acknowledge'), findsOneWidget);
        expect(find.text('Clear'), findsOneWidget);

        // Switch to Relations tab
        await tester.tap(find.text('Relations'));
        await tester.pumpAndSettle();
        expect(find.text('Solar Inverter 01'), findsOneWidget);
        expect(find.text('Contains · DEVICE'), findsOneWidget);
      },
    );

    testWidgets('error state 403 renders Access Restricted', (tester) async {
      await tester.pumpWidget(
        buildApp(
          assetRepo: _FakeAssetRepo(
            throwFailure: const TbFailure(
              type: TbFailureType.permissionDenied,
              message: 'Forbidden',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(TbEmptyState), findsOneWidget);
      expect(find.text('Access Restricted'), findsOneWidget);
    });

    testWidgets('embedded mode renders without top AppBar', (tester) async {
      await tester.pumpWidget(buildApp(embedded: true));
      await tester.pumpAndSettle();

      expect(find.byType(AppBar), findsNothing);
      expect(find.text('Central Solar Farm'), findsOneWidget);
    });

    testWidgets('renders in Dark theme at 2.0x text scale without overflow', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildApp(theme: tbDarkTheme(), textScale: 2.0, disableAnimations: true),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Central Solar Farm'), findsWidgets);
    });
  });
}
