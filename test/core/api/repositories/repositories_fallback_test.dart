import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thingsboard_democloud_app/core/api/client/tb_api_client.dart';
import 'package:thingsboard_democloud_app/core/api/repositories/alarm_repository.dart';
import 'package:thingsboard_democloud_app/core/api/repositories/asset_repository.dart';
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

  group('Rest*Repository PE 4.4.x OpenAPI remap & DemoCloud 3.3.x fallbacks', () {
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
      'DashboardRepository falls back on 404 and /api/user/{userId} UUID 400 collision, but surfaces 403 permissionDenied',
      () async {
        final repo = RestDashboardRepository(client: client);

        // 1) 404 on /api/user/dashboards -> falls back to /api/tenant/dashboards
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

        // 2) TB 3.3 Spring MVC collision: 400 Invalid UUID string: dashboards -> falls back cleanly
        adapter.enqueue(
          'GET',
          '/api/user/dashboards',
          (_) => MockDioAdapter.jsonResponse({
            'status': 400,
            'errorCode': 31,
            'message': 'Invalid UUID string: dashboards',
          }, statusCode: 400),
        );
        final collisionPage = await repo.getDashboards(
          const PageQuery(),
          authority: Authority.tenantAdmin,
        );
        expect(collisionPage.data.single.title, 'Fallback Dash');

        // 3) TB 3.3 collision on /api/user/lastVisitedDashboards & 404 on action -> empty UserDashboardsInfo
        adapter.enqueue(
          'GET',
          '/api/user/lastVisitedDashboards',
          (_) => MockDioAdapter.jsonResponse({
            'status': 400,
            'errorCode': 31,
            'message': 'Invalid UUID string: lastVisitedDashboards',
          }, statusCode: 400),
        );
        final visited = await repo.getLastVisitedDashboards();
        expect(visited.last, isEmpty);
        expect(visited.starred, isEmpty);

        final actionRes = await repo.reportDashboardAction('d-1', 'VISIT');
        expect(actionRes.last, isEmpty);

        // 4) 403 on /api/user/dashboards -> MUST throw TbFailure(permissionDenied), NOT fallback
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
      'TelemetryRepository discovers keys when empty, falls back on 404 only for history, never 400, with useStrictDataTypes=true',
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
            expect(opts.queryParameters['keys'], isNotEmpty);
            return MockDioAdapter.jsonResponse({
              'temperature': [
                {'ts': 1500, 'value': 23.4},
              ],
            });
          },
        );

        final history = await repo.getTimeseriesHistory(query);
        expect(history['temperature']?.single.numericValue, 23.4);

        // Empty keys -> discovers /keys/timeseries first so neither PE 4.4 nor 3.3 throws 400 missing keys.
        adapter.on(
          'GET',
          '/api/plugins/telemetry/DEVICE/dev-1/keys/timeseries',
          (_) => MockDioAdapter.jsonResponse(['temperature', 'humidity']),
        );
        adapter.enqueue(
          'GET',
          '/api/plugins/telemetry/DEVICE/dev-1/values/timeseries/history',
          (opts) {
            expect(opts.queryParameters['keys'], 'temperature,humidity');
            return MockDioAdapter.jsonResponse({
              'status': 404,
            }, statusCode: 404);
          },
        );
        final discoveredHistory = await repo.getTimeseriesHistory(
          const TbTsHistoryQuery(
            entityId: entity,
            keys: [],
            startTs: 1000,
            endTs: 2000,
          ),
        );
        expect(discoveredHistory['temperature']?.single.numericValue, 23.4);

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
      'DeviceRepository maps /api/tenant/deviceInfos params & full DeviceInfo schema accurately without conflicting type+deviceProfileId',
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
        // Simulate strict TB 3.3 Jackson rejecting unknown 'deviceTypes' with 400, accepting singular 'deviceType'.
        adapter.on('POST', '/api/entitiesQuery/count', (opts) {
          final body = opts.data is String
              ? jsonDecode(opts.data as String) as Map<String, dynamic>
              : opts.data as Map<String, dynamic>;
          final ef = body['entityFilter'] as Map<String, dynamic>;
          if (ef.containsKey('deviceTypes')) {
            return MockDioAdapter.jsonResponse({
              'status': 400,
              'message': 'Unrecognized field "deviceTypes"',
            }, statusCode: 400);
          }
          expect(ef, <String, dynamic>{
            'type': 'deviceType',
            'deviceType': 'Thermostat',
            'deviceNameFilter': '',
          });
          final keyFilter =
              (body['keyFilters'] as List).first as Map<String, dynamic>;
          final active =
              ((keyFilter['predicate'] as Map)['value'] as Map)['defaultValue']
                  as bool;
          return MockDioAdapter.jsonResponse(active ? 4 : 1);
        });

        final page = await repo.getDeviceProfiles(const PageQuery());
        expect(page.data.single.activeCount, 4);
        expect(page.data.single.inactiveCount, 1);

        // Pre-4.x fallback: /api/deviceInfos/all returns 404 -> /api/tenant/deviceInfos
        // Must send exact TB 3.3 params (no includeCustomers/active, deviceProfileId='' when unfiltered,
        // and NEVER both deviceProfileId and type simultaneously!).
        final capturedTenantParams = <Map<String, dynamic>>[];
        adapter.on('GET', '/api/tenant/deviceInfos', (opts) {
          capturedTenantParams.add(
            Map<String, dynamic>.from(opts.queryParameters),
          );
          return MockDioAdapter.jsonResponse({
            'data': [
              {
                'id': {
                  'entityType': 'DEVICE',
                  'id': 'c375efb0-c6c1-11f1-81ad-2ba0e9cc8ebb',
                },
                'createdTime': 1791867093547,
                'additionalInfo': {
                  'gateway': false,
                  'overwriteActivityTime': false,
                  'description': '',
                },
                'tenantId': {
                  'entityType': 'TENANT',
                  'id': '3c1c4990-6a2f-11f1-a5d9-33385914568a',
                },
                'customerId': {
                  'entityType': 'CUSTOMER',
                  'id': '13814000-1dd2-11b2-8080-808080808080',
                },
                'name': 'bringter_flood',
                'type': 'Bringter Flood',
                'label': '',
                'deviceProfileId': {
                  'entityType': 'DEVICE_PROFILE',
                  'id': '3c24d510-6a2f-11f1-a5d9-33385914568a',
                },
                'deviceData': {
                  'configuration': {'type': 'DEFAULT'},
                  'transportConfiguration': {'type': 'DEFAULT'},
                },
                'firmwareId': {
                  'entityType': 'OTA_PACKAGE',
                  'id': 'e126ef40-d347-11f1-991a-2ba0e9cc8ebb',
                },
                'softwareId': null,
                'customerTitle': null,
                'customerIsPublic': false,
                'deviceProfileName': 'Bringter Flood',
              },
            ],
            'totalPages': 1,
            'totalElements': 1,
            'hasNext': false,
          });
        });
        adapter.on('POST', '/api/entitiesQuery/find', (_) {
          return MockDioAdapter.jsonResponse({
            'data': [
              {
                'entityId': {
                  'entityType': 'DEVICE',
                  'id': 'c375efb0-c6c1-11f1-81ad-2ba0e9cc8ebb',
                },
                'latest': {
                  'SERVER_ATTRIBUTE': {
                    'active': {'ts': 1000, 'value': 'true'},
                  },
                },
              },
            ],
            'totalPages': 1,
            'totalElements': 1,
            'hasNext': false,
          });
        });

        // 1) Unfiltered query -> deviceProfileId='' and NO includeCustomers / type / active
        final devicesPage = await repo.getDevices(
          const PageQuery(pageSize: 10, page: 0),
          const TbDeviceQuery(),
        );
        expect(capturedTenantParams.first, <String, dynamic>{
          'pageSize': 10,
          'page': 0,
          'sortProperty': 'createdTime',
          'sortOrder': 'DESC',
          'deviceProfileId': '',
        });
        final parsedDev = devicesPage.data.single;
        expect(parsedDev.active, isTrue);
        expect(parsedDev.tenantId, '3c1c4990-6a2f-11f1-a5d9-33385914568a');
        expect(parsedDev.customerId, isNull); // NULL UUID normalized to null
        expect(
          parsedDev.deviceProfileId,
          '3c24d510-6a2f-11f1-a5d9-33385914568a',
        );
        expect(parsedDev.deviceProfileName, 'Bringter Flood');
        expect(parsedDev.firmwareId, 'e126ef40-d347-11f1-991a-2ba0e9cc8ebb');
        expect(parsedDev.customerIsPublic, isFalse);

        // 2) Both deviceProfileId and deviceType provided -> sends ONLY deviceProfileId, NEVER 'type'
        await repo.getDevices(
          const PageQuery(pageSize: 10, page: 0),
          const TbDeviceQuery(
            deviceProfileId: '3c24d510-6a2f-11f1-a5d9-33385914568a',
            deviceType: 'Bringter Flood',
          ),
        );
        expect(capturedTenantParams.last.containsKey('type'), isFalse);
        expect(
          capturedTenantParams.last['deviceProfileId'],
          '3c24d510-6a2f-11f1-a5d9-33385914568a',
        );

        // getDeviceInfo enriches missing 'active' from SERVER_SCOPE attributes.
        adapter.on(
          'GET',
          '/api/device/info/dev-live-1',
          (_) => MockDioAdapter.jsonResponse({
            'id': {'entityType': 'DEVICE', 'id': 'dev-live-1'},
            'name': 'Flood Sensor 1',
            'type': 'Bringter Flood',
          }),
        );
        adapter.on(
          'GET',
          '/api/plugins/telemetry/DEVICE/dev-live-1/values/attributes/SERVER_SCOPE',
          (_) => MockDioAdapter.jsonResponse([
            {'key': 'active', 'value': true, 'lastUpdateTs': 1234},
          ]),
        );

        final detail = await repo.getDeviceInfo('dev-live-1');
        expect(detail.active, isTrue);
      },
    );

    test(
      'AlarmRepository formats CSV lists per PE 4.4 OpenAPI and falls back to /api/alarms on 404',
      () async {
        final repo = RestAlarmRepository(client: client);

        adapter.enqueue('GET', '/api/v2/alarms', (opts) {
          expect(opts.queryParameters['statusList'], 'ACTIVE,UNACK');
          expect(opts.queryParameters['severityList'], 'CRITICAL');
          return MockDioAdapter.jsonResponse({'status': 404}, statusCode: 404);
        });
        adapter.on('GET', '/api/alarms', (opts) {
          expect(opts.queryParameters['fetchOriginator'], true);
          return MockDioAdapter.jsonResponse({
            'data': [
              {
                'id': {'entityType': 'ALARM', 'id': 'a-1'},
                'type': 'High Water',
                'severity': 'CRITICAL',
                'acknowledged': false,
                'cleared': false,
                'createdTime': 1000,
              },
            ],
            'totalPages': 1,
            'totalElements': 1,
            'hasNext': false,
          });
        });

        final alarms = await repo.getAlarms(
          const PageQuery(),
          const TbAlarmFilter(
            statusList: {AlarmSearchStatus.active, AlarmSearchStatus.unack},
            severityList: {AlarmSeverity.critical},
          ),
        );
        expect(alarms.data.single.type, 'High Water');
      },
    );

    test(
      'AssetRepository falls back from PE 4.4 /api/relations/info/from/* to query-param /api/relations/info on 404',
      () async {
        final repo = RestAssetRepository(client: client);
        adapter.on('GET', '/api/relations/info', (opts) {
          expect(opts.queryParameters['fromId'], 'ast-1');
          expect(opts.queryParameters['fromType'], 'ASSET');
          return MockDioAdapter.jsonResponse([
            {
              'from': {'entityType': 'ASSET', 'id': 'ast-1'},
              'to': {'entityType': 'DEVICE', 'id': 'dev-1'},
              'type': 'Contains',
              'fromName': 'Building A',
              'toName': 'Sensor 1',
            },
          ]);
        });

        final rels = await repo.getRelations(
          const EntityId(entityType: EntityType.asset, id: 'ast-1'),
        );
        expect(rels.single.toName, 'Sensor 1');
      },
    );

    test(
      'NotificationRepository supports settings, X-Mobile-Token session, and graceful 404 unread count',
      () async {
        final repo = RestNotificationRepository(client: client);
        // Default MockDioAdapter returns 404 for /api/notifications/unread/count
        expect(await repo.getUnreadCount(), 0);

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
