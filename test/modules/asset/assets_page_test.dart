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
import 'package:thingsboard_democloud_app/modules/asset/assets_page.dart';
import 'package:thingsboard_democloud_app/widgets/icons/tb_icons.dart';
import 'package:thingsboard_democloud_app/widgets/tb_empty_state.dart';

import '../../helpers/fake_app_preferences.dart';
import '../../helpers/fake_secure_storage.dart';
import '../../helpers/fake_ws_channel.dart';
import '../../helpers/mock_dio_adapter.dart';

class _FakeAssetRepo implements AssetRepository {
  _FakeAssetRepo({
    this.assets = const [],
    this.profiles = const [],
    this.throwFailure,
  });

  List<TbAssetInfo> assets;
  List<TbAssetProfileInfo> profiles;
  TbFailure? throwFailure;

  @override
  Future<PageData<TbAssetInfo>> getAssets(
    PageQuery query,
    TbAssetQuery filter, {
    CancelToken? cancelToken,
  }) async {
    if (throwFailure != null) throw throwFailure!;

    final search = filter.textSearch?.toLowerCase() ?? '';
    final profileId = filter.assetProfileId;

    final filtered = assets.where((a) {
      if (profileId != null && a.assetProfileId != profileId) return false;
      if (search.isNotEmpty &&
          !a.name.toLowerCase().contains(search) &&
          !a.type.toLowerCase().contains(search)) {
        return false;
      }
      return true;
    }).toList();

    return PageData<TbAssetInfo>(
      data: filtered,
      totalPages: 1,
      totalElements: filtered.length,
      hasNext: false,
    );
  }

  @override
  Future<TbAssetInfo> getAssetInfo(String assetId) async {
    return assets.firstWhere(
      (a) => a.id == assetId,
      orElse: () =>
          TbAssetInfo(id: assetId, name: 'Asset $assetId', type: 'Building'),
    );
  }

  @override
  Future<PageData<TbAssetProfileInfo>> getAssetProfiles(PageQuery query) async {
    return PageData<TbAssetProfileInfo>(
      data: profiles,
      totalPages: 1,
      totalElements: profiles.length,
      hasNext: false,
    );
  }

  @override
  Future<List<TbEntityRelationInfo>> getRelations(
    EntityId entity, {
    bool outgoing = true,
  }) async {
    return const [];
  }
}

class _FakeTelemetryRepo implements TelemetryRepository {
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
  }) async => const {};

  @override
  Future<Map<String, List<TbTsPoint>>> getTimeseriesHistory(
    TbTsHistoryQuery query, {
    CancelToken? cancelToken,
  }) async => const {};
}

class _FakeAlarmRepo implements AlarmRepository {
  @override
  Future<PageData<TbAlarmInfo>> getAlarms(
    PageQuery query,
    TbAlarmFilter filter, {
    CancelToken? cancelToken,
  }) async =>
      const PageData(data: [], totalPages: 1, totalElements: 0, hasNext: false);

  @override
  Future<TbAlarmInfo> getAlarmInfo(String alarmId) async =>
      throw UnimplementedError();

  @override
  Future<TbAlarmInfo> ackAlarm(String alarmId) async =>
      throw UnimplementedError();

  @override
  Future<TbAlarmInfo> clearAlarm(String alarmId) async =>
      throw UnimplementedError();

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

final _sampleProfiles = [
  const TbAssetProfileInfo(id: 'prof-1', name: 'Facilities'),
  const TbAssetProfileInfo(id: 'prof-2', name: 'Warehouses'),
];

final _sampleAssets = [
  const TbAssetInfo(
    id: 'a-1',
    name: 'Berlin Solar Facility',
    type: 'Facility',
    assetProfileId: 'prof-1',
    ownerName: 'Green Energy',
  ),
  const TbAssetInfo(
    id: 'a-2',
    name: 'Hamburg Central Depot',
    type: 'Depot',
    assetProfileId: 'prof-2',
    ownerName: 'North Logistics',
  ),
];

void main() {
  Widget buildApp({
    required AssetRepository repo,
    Size size = const Size(390, 844),
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
        assetRepositoryProvider.overrideWithValue(repo),
        telemetryRepositoryProvider.overrideWithValue(_FakeTelemetryRepo()),
        alarmRepositoryProvider.overrideWithValue(_FakeAlarmRepo()),
      ],
      child: MediaQuery(
        data: MediaQueryData(
          size: size,
          textScaler: TextScaler.linear(textScale),
          disableAnimations: disableAnimations,
        ),
        child: MaterialApp(
          theme: theme ?? tbLightTheme(),
          home: const AssetsPage(),
        ),
      ),
    );
  }

  group('AssetsPage', () {
    testWidgets('renders assets list and profile filter chips', (tester) async {
      final repo = _FakeAssetRepo(
        assets: _sampleAssets,
        profiles: _sampleProfiles,
      );
      await tester.pumpWidget(buildApp(repo: repo));
      await tester.pumpAndSettle();

      expect(find.text('Assets'), findsOneWidget);
      expect(find.text('Berlin Solar Facility'), findsOneWidget);
      expect(find.text('Hamburg Central Depot'), findsOneWidget);
      expect(find.text('Facilities'), findsOneWidget);
      expect(find.text('Warehouses'), findsOneWidget);
      expect(find.byType(TbIcon), findsWidgets);
    });

    testWidgets('tapping profile filter chip filters asset list', (
      tester,
    ) async {
      final repo = _FakeAssetRepo(
        assets: _sampleAssets,
        profiles: _sampleProfiles,
      );
      await tester.pumpWidget(buildApp(repo: repo));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Facilities'));
      await tester.pumpAndSettle();

      expect(find.text('Berlin Solar Facility'), findsOneWidget);
      expect(find.text('Hamburg Central Depot'), findsNothing);
    });

    testWidgets('search bar filters assets by name', (tester) async {
      final repo = _FakeAssetRepo(
        assets: _sampleAssets,
        profiles: _sampleProfiles,
      );
      await tester.pumpWidget(buildApp(repo: repo));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Search assets'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'Hamburg');
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();

      expect(find.text('Hamburg Central Depot'), findsOneWidget);
      expect(find.text('Berlin Solar Facility'), findsNothing);
    });

    testWidgets('empty list renders TbEmptyState', (tester) async {
      final repo = _FakeAssetRepo(assets: []);
      await tester.pumpWidget(buildApp(repo: repo));
      await tester.pumpAndSettle();

      expect(find.byType(TbEmptyState), findsOneWidget);
      expect(find.text('No assets available'), findsOneWidget);
    });

    testWidgets('403 error renders Access Restricted empty state', (
      tester,
    ) async {
      final repo = _FakeAssetRepo(
        throwFailure: const TbFailure(
          type: TbFailureType.permissionDenied,
          message: 'Denied',
        ),
      );
      await tester.pumpWidget(buildApp(repo: repo));
      await tester.pumpAndSettle();

      expect(find.byType(TbEmptyState), findsOneWidget);
      expect(find.text('Access Restricted'), findsOneWidget);
    });

    testWidgets('adaptive 2-pane renders side by side on >=840dp', (
      tester,
    ) async {
      final repo = _FakeAssetRepo(
        assets: _sampleAssets,
        profiles: _sampleProfiles,
      );
      await tester.pumpWidget(
        buildApp(repo: repo, size: const Size(1024, 768)),
      );
      await tester.pumpAndSettle();

      expect(find.byType(VerticalDivider), findsOneWidget);
      expect(find.byType(AssetDetailsPage), findsOneWidget);
      expect(find.text('Berlin Solar Facility'), findsWidgets);
    });

    testWidgets('renders in Dark mode at 2.0x text scale without overflow', (
      tester,
    ) async {
      final repo = _FakeAssetRepo(
        assets: _sampleAssets,
        profiles: _sampleProfiles,
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
      expect(find.text('Assets'), findsOneWidget);
      expect(find.text('Berlin Solar Facility'), findsOneWidget);
    });
  });
}
