import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thingsboard_democloud_app/core/api/client/tb_api_client.dart';
import 'package:thingsboard_democloud_app/core/api/repositories/customer_repository.dart';
import 'package:thingsboard_democloud_app/core/api/repositories/dashboard_repository.dart';
import 'package:thingsboard_democloud_app/core/api/repositories/device_repository.dart';
import 'package:thingsboard_democloud_app/core/api/repositories/notification_repository.dart';
import 'package:thingsboard_democloud_app/core/api/repositories/rpc_repository.dart';
import 'package:thingsboard_democloud_app/core/api/repositories/server_config_repository.dart';
import 'package:thingsboard_democloud_app/core/api/repositories/telemetry_repository.dart';
import 'package:thingsboard_democloud_app/core/mock/mock_data.dart';
import 'package:thingsboard_democloud_app/core/models/models.dart';

import '../../../helpers/fake_secure_storage.dart';
import '../../../helpers/mock_dio_adapter.dart';

void main() {
  late MockDioAdapter adapter;
  late FakeSecureStorage storage;
  late TbApiClient client;

  setUp(() {
    adapter = MockDioAdapter();
    storage = FakeSecureStorage();
    client = TbApiClient(
      baseUrl: 'https://thingsboard.democloud.xyz/',
      storage: storage,
      httpClientAdapter: adapter,
    );
  });

  group('Rest*Repository 404-only fallbacks & 403 RBAC preservation', () {
    test(
      'ServerConfigRepository treats 404 on mobile/whiteLabel as null',
      () async {
        adapter.on(
          'GET',
          '/api/noauth/userPasswordPolicy',
          (_) => MockDioAdapter.jsonResponse({'minimumLength': 8}),
        );
        adapter.on(
          'POST',
          '/api/noauth/oauth2Clients',
          (_) => MockDioAdapter.jsonResponse([]),
        );
        // /api/noauth/mobile and /api/noauth/whiteLabel/... default to 404 in MockDioAdapter

        final repo = RestServerConfigRepository(client: client);
        expect((await repo.fetchPasswordPolicy())?.minimumLength, 8);
        expect(
          await repo.fetchOAuth2Clients(pkgName: 'pkg', platform: 'ANDROID'),
          isEmpty,
        );
        expect(
          await repo.fetchMobileInfo(pkgName: 'pkg', platform: 'ANDROID'),
          isNull,
        );
        expect(await repo.fetchWhiteLabelParams(), isNull);
      },
    );

    test(
      'DashboardRepository falls back on 404, but surfaces 403 permissionDenied',
      () async {
        final repo = RestDashboardRepository(client: client);

        // 404 on /api/user/dashboards -> falls back to /api/tenant/dashboards
        adapter.enqueue(
          'GET',
          '/api/user/dashboards',
          (_) => MockDioAdapter.jsonResponse({'status': 404}, statusCode: 404),
        );
        adapter.on(
          'GET',
          '/api/tenant/dashboards',
          (_) => MockDioAdapter.jsonResponse({
            'data': [
              {
                'id': {'entityType': 'DASHBOARD', 'id': 'd-1'},
                'title': 'Fallback Dash',
              },
            ],
            'totalPages': 1,
            'totalElements': 1,
            'hasNext': false,
          }),
        );

        final page = await repo.getDashboards(
          const PageQuery(),
          authority: Authority.tenantAdmin,
        );
        expect(page.data.single.title, 'Fallback Dash');

        // 403 on /api/user/dashboards -> MUST throw TbFailure(permissionDenied), NOT fallback
        adapter.enqueue(
          'GET',
          '/api/user/dashboards',
          (_) => MockDioAdapter.jsonResponse({
            'status': 403,
            'errorCode': 20,
            'message': 'Permission denied',
          }, statusCode: 403),
        );

        await expectLater(
          repo.getDashboards(
            const PageQuery(),
            authority: Authority.tenantAdmin,
          ),
          throwsA(
            isA<TbFailure>().having(
              (f) => f.type,
              'type',
              TbFailureType.permissionDenied,
            ),
          ),
        );
      },
    );

    test(
      'CustomerRepository falls back on 404, but surfaces 403 permissionDenied',
      () async {
        final repo = RestCustomerRepository(client: client);

        adapter.enqueue(
          'GET',
          '/api/customerInfos/all',
          (_) => MockDioAdapter.jsonResponse({'status': 404}, statusCode: 404),
        );
        adapter.on(
          'GET',
          '/api/customers',
          (_) => MockDioAdapter.jsonResponse({
            'data': [
              {
                'id': {'entityType': 'CUSTOMER', 'id': 'c-1'},
                'title': 'Acme',
              },
            ],
            'totalPages': 1,
            'totalElements': 1,
            'hasNext': false,
          }),
        );

        final page = await repo.getCustomers(const PageQuery());
        expect(page.data.single.title, 'Acme');

        adapter.enqueue(
          'GET',
          '/api/customerInfos/all',
          (_) => MockDioAdapter.jsonResponse({
            'status': 403,
            'errorCode': 20,
            'message': 'Forbidden',
          }, statusCode: 403),
        );

        await expectLater(
          repo.getCustomers(const PageQuery()),
          throwsA(
            isA<TbFailure>().having(
              (f) => f.type,
              'type',
              TbFailureType.permissionDenied,
            ),
          ),
        );
      },
    );

    test(
      'TelemetryRepository falls back on 404 only for history, never 400, with useStrictDataTypes=true',
      () async {
        final repo = RestTelemetryRepository(client: client);
        const entity = EntityId(entityType: EntityType.device, id: 'dev-1');
        final query = TbTsHistoryQuery(
          entityId: entity,
          keys: const ['temperature'],
          startTs: 1000,
          endTs: 2000,
          agg: TsAggregation.avg,
          intervalMs: 60000,
        );

        adapter.enqueue(
          'GET',
          '/api/plugins/telemetry/DEVICE/dev-1/values/timeseries/history',
          (_) => MockDioAdapter.jsonResponse({'status': 404}, statusCode: 404),
        );
        adapter.on(
          'GET',
          '/api/plugins/telemetry/DEVICE/dev-1/values/timeseries',
          (opts) {
            expect(opts.queryParameters['useStrictDataTypes'], true);
            return MockDioAdapter.jsonResponse({
              'temperature': [
                {'ts': 1500, 'value': 23.4},
              ],
            });
          },
        );

        final history = await repo.getTimeseriesHistory(query);
        expect(history['temperature']?.single.numericValue, 23.4);

        // 400 BAD_REQUEST_PARAMS must NOT fall back.
        adapter.enqueue(
          'GET',
          '/api/plugins/telemetry/DEVICE/dev-1/values/timeseries/history',
          (_) => MockDioAdapter.jsonResponse({
            'status': 400,
            'errorCode': 31,
            'message': 'Invalid interval',
          }, statusCode: 400),
        );

        await expectLater(
          repo.getTimeseriesHistory(query),
          throwsA(
            isA<TbFailure>().having(
              (f) => f.type,
              'type',
              TbFailureType.validation,
            ),
          ),
        );
      },
    );

    test(
      'DeviceRepository sends exact entitiesQuery/count body for profile active/inactive counts',
      () async {
        final repo = RestDeviceRepository(client: client);

        adapter.on(
          'GET',
          '/api/deviceProfileInfos',
          (_) => MockDioAdapter.jsonResponse({
            'data': [
              {
                'id': {'entityType': 'DEVICE_PROFILE', 'id': 'dp-1'},
                'name': 'Thermostat',
                'transportType': 'DEFAULT',
              },
            ],
            'totalPages': 1,
            'totalElements': 1,
            'hasNext': false,
          }),
        );
        adapter.on('POST', '/api/entitiesQuery/count', (opts) {
          final body = opts.data is String
              ? jsonDecode(opts.data as String) as Map<String, dynamic>
              : opts.data as Map<String, dynamic>;
          expect(body['entityFilter'], <String, dynamic>{
            'type': 'deviceType',
            'deviceTypes': ['Thermostat'],
            'deviceNameFilter': '',
          });
          final keyFilter =
              (body['keyFilters'] as List).first as Map<String, dynamic>;
          expect(keyFilter['key'], {
            'type': 'SERVER_ATTRIBUTE',
            'key': 'active',
          });
          final active =
              ((keyFilter['predicate'] as Map)['value'] as Map)['defaultValue']
                  as bool;
          return MockDioAdapter.jsonResponse(active ? 4 : 1);
        });

        final page = await repo.getDeviceProfiles(const PageQuery());
        expect(page.data.single.activeCount, 4);
        expect(page.data.single.inactiveCount, 1);
      },
    );

    test(
      'NotificationRepository supports settings and X-Mobile-Token session',
      () async {
        final repo = RestNotificationRepository(client: client);
        adapter.on(
          'GET',
          '/api/notification/settings/user',
          (_) => MockDioAdapter.jsonResponse({
            'prefs': {
              'ALARM': {'WEB': true},
            },
          }),
        );
        adapter.on(
          'POST',
          '/api/notification/settings/user',
          (opts) => MockDioAdapter.jsonResponse(opts.data),
        );
        adapter.on('POST', '/api/user/mobile/session', (opts) {
          expect(opts.headers['X-Mobile-Token'], 'fcm-123');
          return MockDioAdapter.emptyResponse();
        });

        final settings = await repo.getNotificationSettings();
        expect(settings.prefs['ALARM'], {'WEB': true});
        await repo.saveNotificationSettings(settings);
        await repo.registerMobileSession('fcm-123');
      },
    );

    test(
      'DemoRpcRepository echoes active device and throws 504 on offline device',
      () async {
        final repo = DemoRpcRepository([
          MockDevice(
            id: 'dev-1',
            name: 'ActiveDev',
            label: '',
            type: 'Thermostat',
            active: true,
            createdTime: DateTime(2026),
            customerName: 'Acme',
            telemetry: const {},
          ),
          MockDevice(
            id: 'dev-6',
            name: 'OfflineDev',
            label: '',
            type: 'Water Sensor',
            active: false,
            createdTime: DateTime(2026),
            customerName: 'City',
            telemetry: const {},
          ),
        ]);

        final reply = await repo.sendTwoWayRpc(
          'dev-1',
          const TbRpcRequest(method: 'ping', params: {'v': 1}),
        );
        expect(reply?['status'], 'OK');

        await expectLater(
          repo.sendTwoWayRpc(
            'dev-6',
            const TbRpcRequest(method: 'setPumpState'),
            cancelToken: CancelToken(),
          ),
          throwsA(
            isA<TbFailure>().having(
              (f) => f.type,
              'type',
              TbFailureType.deviceOfflineOrTimeout,
            ),
          ),
        );
      },
    );
  });
}
