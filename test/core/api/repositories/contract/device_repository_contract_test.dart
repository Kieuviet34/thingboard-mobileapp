import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thingsboard_democloud_app/core/api/client/tb_api_client.dart';
import 'package:thingsboard_democloud_app/core/api/repositories/device_repository.dart';
import 'package:thingsboard_democloud_app/core/models/models.dart';

import '../../../../helpers/fake_secure_storage.dart';
import '../../../../helpers/mock_dio_adapter.dart';
import '../../../../helpers/openapi_contract.dart';

/// Contract test: every request `RestDeviceRepository` sends must exist in the
/// ThingsBoard 4.4.x OpenAPI, and every response shape must parse correctly.
void main() {
  late MockDioAdapter adapter;
  late RestDeviceRepository repo;
  final contract = OpenApiContract.load();

  // Shape: DeviceInfo (spec schema).
  const deviceJson = <String, dynamic>{
    'id': {'entityType': 'DEVICE', 'id': 'd-1'},
    'createdTime': 1700000000000,
    'tenantId': {'entityType': 'TENANT', 'id': 't-1'},
    'customerId': {'entityType': 'CUSTOMER', 'id': 'c-1'},
    'name': 'Thermostat 1',
    'type': 'Thermostat',
    'label': 'Lobby',
    'deviceProfileId': {'entityType': 'DEVICE_PROFILE', 'id': 'dp-1'},
    'version': 1,
    'ownerName': 'Acme',
    'groups': <dynamic>[],
    'active': true,
    'ownerId': {'entityType': 'CUSTOMER', 'id': 'c-1'},
    'additionalInfo': {'description': 'Ground floor'},
  };

  // Shape: DeviceProfileInfo (spec schema).
  const profileJson = <String, dynamic>{
    'id': {'entityType': 'DEVICE_PROFILE', 'id': 'dp-1'},
    'tenantId': {'entityType': 'TENANT', 'id': 't-1'},
    'name': 'Thermostat',
    'image': 'profile.png',
    'defaultDashboardId': {'entityType': 'DASHBOARD', 'id': 'db-1'},
    'type': 'DEFAULT',
    'transportType': 'MQTT',
  };

  // Shape: Device (claim response payload, spec schema `Device`).
  const claimedDeviceJson = <String, dynamic>{
    'id': {'entityType': 'DEVICE', 'id': 'd-9'},
    'createdTime': 1700000000005,
    'tenantId': {'entityType': 'TENANT', 'id': 't-1'},
    'customerId': {'entityType': 'CUSTOMER', 'id': 'c-1'},
    'name': 'SN-001',
    'type': 'Thermostat',
    'label': '',
    'deviceProfileId': {'entityType': 'DEVICE_PROFILE', 'id': 'dp-1'},
    'version': 1,
    'additionalInfo': {},
  };

  Map<String, dynamic> page(List<Map<String, dynamic>> items) => {
    'data': items,
    'totalPages': 1,
    'totalElements': items.length,
    'hasNext': false,
  };

  /// Body the app sends to `/api/entitiesQuery/count` for one profile.
  Map<String, dynamic> countBody({required bool active}) => {
    'entityFilter': {
      'type': 'deviceType',
      'deviceTypes': ['Thermostat'],
      'deviceNameFilter': '',
    },
    'keyFilters': [
      {
        'key': {'type': 'SERVER_ATTRIBUTE', 'key': 'active'},
        'valueType': 'BOOLEAN',
        'predicate': {
          'type': 'BOOLEAN',
          'operation': 'EQUAL',
          'value': {'defaultValue': active},
        },
      },
    ],
  };

  /// Reads the active/inactive flag out of the count request the app sent.
  bool countsActive(RequestOptions options) {
    final body = options.data as Map<String, dynamic>;
    final keyFilter =
        (body['keyFilters'] as List<dynamic>).single as Map<String, dynamic>;
    final predicate = keyFilter['predicate'] as Map<String, dynamic>;
    final value = predicate['value'] as Map<String, dynamic>;
    return value['defaultValue'] as bool;
  }

  setUp(() {
    adapter = MockDioAdapter();
    repo = RestDeviceRepository(
      client: TbApiClient(
        baseUrl: 'https://thingsboard.democloud.xyz/',
        storage: FakeSecureStorage(),
        httpClientAdapter: adapter,
      ),
    );
  });

  test(
    'getDevices (all filters) sends spec-valid query and parses page',
    () async {
      adapter.on(
        'GET',
        '/api/deviceInfos/all',
        (_) => MockDioAdapter.jsonResponse(page([deviceJson])),
      );

      final result = await repo.getDevices(
        const PageQuery(
          page: 2,
          pageSize: 10,
          textSearch: 'therm',
          sortProperty: 'name',
          sortOrder: SortOrder.asc,
        ),
        const TbDeviceQuery(
          deviceProfileId: 'dp-1',
          active: true,
          textSearch: 'therm',
        ),
      );

      contract.expectAllConform(adapter);
      expect(adapter.capturedRequests.single.queryParameters, {
        'page': 2,
        'pageSize': 10,
        'textSearch': 'therm',
        'sortProperty': 'name',
        'sortOrder': 'ASC',
        'includeCustomers': true,
        'deviceProfileId': 'dp-1',
        'active': true,
      });
      final device = result.data.single;
      expect(device.id, 'd-1');
      expect(device.name, 'Thermostat 1');
      expect(device.type, 'Thermostat');
      expect(device.label, 'Lobby');
      expect(device.deviceProfileId, 'dp-1');
      expect(device.customerId, 'c-1');
      expect(device.ownerName, 'Acme');
      expect(device.active, isTrue);
      expect(device.createdTime, 1700000000000);
      expect(result.totalElements, 1);
      expect(result.hasNext, isFalse);
      expect(
        contract.coveredOperations(adapter.capturedRequests),
        contains('GET /api/deviceInfos/all'),
      );
    },
  );

  test(
    'getDevices drops blank/empty filters and still sends active=false',
    () async {
      adapter.on(
        'GET',
        '/api/deviceInfos/all',
        (_) => MockDioAdapter.jsonResponse(page([])),
      );

      await repo.getDevices(
        const PageQuery(),
        const TbDeviceQuery(
          deviceProfileId: '',
          active: false,
          textSearch: '  ',
        ),
      );

      contract.expectAllConform(adapter);
      expect(adapter.capturedRequests.single.queryParameters, {
        'page': 0,
        'pageSize': 20,
        'sortProperty': 'createdTime',
        'sortOrder': 'DESC',
        'includeCustomers': true,
        'active': false,
      });
    },
  );

  test(
    'getDevices falls back to /api/tenant/deviceInfos only on HTTP 404',
    () async {
      adapter
        ..enqueue(
          'GET',
          '/api/deviceInfos/all',
          (_) => MockDioAdapter.jsonResponse({'status': 404}, statusCode: 404),
        )
        ..on(
          'GET',
          '/api/tenant/deviceInfos',
          (_) => MockDioAdapter.jsonResponse(page([deviceJson])),
        );

      final result = await repo.getDevices(
        const PageQuery(),
        const TbDeviceQuery(),
      );

      contract.expectAllConform(adapter);
      expect(adapter.capturedRequests.map((r) => r.path).toList(), [
        '/api/deviceInfos/all',
        '/api/tenant/deviceInfos',
      ]);
      expect(result.data.single.id, 'd-1');
      expect(
        contract.coveredOperations(adapter.capturedRequests),
        contains('GET /api/deviceInfos/all'),
      );
    },
  );

  test('getDevices rethrows HTTP 403 without the tenant fallback', () async {
    adapter.on(
      'GET',
      '/api/deviceInfos/all',
      (_) => MockDioAdapter.jsonResponse({'status': 403}, statusCode: 403),
    );

    await expectLater(
      repo.getDevices(const PageQuery(), const TbDeviceQuery()),
      throwsA(
        isA<TbFailure>().having(
          (f) => f.type,
          'type',
          TbFailureType.permissionDenied,
        ),
      ),
    );

    contract.expectAllConform(adapter);
    expect(
      adapter.capturedRequests.map((r) => r.path),
      isNot(contains('/api/tenant/deviceInfos')),
    );
  });

  test(
    'getDeviceProfiles sends spec query, parses profile and active/inactive counts',
    () async {
      adapter
        ..on(
          'GET',
          '/api/deviceProfileInfos',
          (_) => MockDioAdapter.jsonResponse(page([profileJson])),
        )
        ..on(
          'POST',
          '/api/entitiesQuery/count',
          (o) => MockDioAdapter.jsonResponse(countsActive(o) ? 3 : 1),
        );

      final result = await repo.getDeviceProfiles(
        const PageQuery(textSearch: 'Thermo'),
      );

      contract.expectAllConform(adapter);
      expect(adapter.capturedRequests.first.path, '/api/deviceProfileInfos');
      expect(adapter.capturedRequests.first.queryParameters, {
        'page': 0,
        'pageSize': 20,
        'textSearch': 'Thermo',
        'sortProperty': 'createdTime',
        'sortOrder': 'DESC',
      });

      final profile = result.data.single;
      expect(profile.id, 'dp-1');
      expect(profile.name, 'Thermostat');
      expect(profile.image, 'profile.png');
      expect(profile.defaultDashboardId, 'db-1');
      expect(profile.transportType, 'MQTT');
      expect(profile.activeCount, 3);
      expect(profile.inactiveCount, 1);

      final counts = adapter.capturedRequests
          .where((r) => r.path == '/api/entitiesQuery/count')
          .toList();
      expect(
        counts.map((r) => r.data),
        unorderedEquals([countBody(active: true), countBody(active: false)]),
      );
      expect(
        contract.coveredOperations(adapter.capturedRequests),
        containsAll(<String>[
          'GET /api/deviceProfileInfos',
          'POST /api/entitiesQuery/count',
        ]),
      );
    },
  );

  test(
    'getDeviceProfiles counts via /api/deviceInfos/all when entitiesQuery/count is 404',
    () async {
      adapter
        ..enqueue(
          'POST',
          '/api/entitiesQuery/count',
          (_) => MockDioAdapter.jsonResponse({'status': 404}, statusCode: 404),
        )
        ..enqueue(
          'POST',
          '/api/entitiesQuery/count',
          (_) => MockDioAdapter.jsonResponse({'status': 404}, statusCode: 404),
        )
        ..on(
          'GET',
          '/api/deviceProfileInfos',
          (_) => MockDioAdapter.jsonResponse(page([profileJson])),
        )
        ..on(
          'GET',
          '/api/deviceInfos/all',
          (o) => MockDioAdapter.jsonResponse({
            'data': <dynamic>[],
            'totalPages': 1,
            'totalElements': o.queryParameters['active'] == true ? 2 : 5,
            'hasNext': false,
          }),
        );

      final result = await repo.getDeviceProfiles(const PageQuery());

      contract.expectAllConform(adapter);
      final profile = result.data.single;
      expect(profile.activeCount, 2);
      expect(profile.inactiveCount, 5);

      final fallbacks = adapter.capturedRequests
          .where((r) => r.path == '/api/deviceInfos/all')
          .toList();
      expect(
        fallbacks.map((r) => r.queryParameters),
        unorderedEquals([
          {'pageSize': 1, 'page': 0, 'deviceProfileId': 'dp-1', 'active': true},
          {
            'pageSize': 1,
            'page': 0,
            'deviceProfileId': 'dp-1',
            'active': false,
          },
        ]),
      );
      expect(
        contract.coveredOperations(adapter.capturedRequests),
        containsAll(<String>[
          'GET /api/deviceProfileInfos',
          'GET /api/deviceInfos/all',
          'POST /api/entitiesQuery/count',
        ]),
      );
    },
  );

  test('getDeviceInfo uses /api/device/info/{deviceId}', () async {
    adapter.on(
      'GET',
      '/api/device/info/d-1',
      (_) => MockDioAdapter.jsonResponse(deviceJson),
    );

    final device = await repo.getDeviceInfo('d-1');

    contract.expectAllConform(adapter);
    expect(device.id, 'd-1');
    expect(device.name, 'Thermostat 1');
    expect(device.active, isTrue);
    expect(device.deviceProfileId, 'dp-1');
    expect(device.customerId, 'c-1');
    expect(
      contract.coveredOperations(adapter.capturedRequests),
      contains('GET /api/device/info/{deviceId}'),
    );
  });

  test(
    'getDeviceCredentials uses /api/device/{deviceId}/credentials',
    () async {
      adapter.on(
        'GET',
        '/api/device/d-1/credentials',
        (_) => MockDioAdapter.jsonResponse({
          'id': {'id': 'cr-1'},
          'createdTime': 1700000000010,
          'deviceId': {'entityType': 'DEVICE', 'id': 'd-1'},
          'credentialsType': 'ACCESS_TOKEN',
          'credentialsId': 'cid-1',
          'credentialsValue': 'tok-1',
          'version': 1,
        }),
      );

      final credentials = await repo.getDeviceCredentials('d-1');

      contract.expectAllConform(adapter);
      expect(credentials.id, 'cr-1');
      expect(credentials.deviceId, 'd-1');
      expect(credentials.credentialsType, 'ACCESS_TOKEN');
      expect(credentials.credentialsId, 'cid-1');
      expect(credentials.credentialsValue, 'tok-1');
      expect(
        contract.coveredOperations(adapter.capturedRequests),
        contains('GET /api/device/{deviceId}/credentials'),
      );
    },
  );

  test('claimDevice sends secretKey in body and parses result', () async {
    adapter.on(
      'POST',
      '/api/customer/device/SN-001/claim',
      (_) => MockDioAdapter.jsonResponse({
        'response': 'SUCCESS',
        'device': claimedDeviceJson,
      }),
    );

    final result = await repo.claimDevice('SN-001', secretKey: 'SECRET');

    contract.expectAllConform(adapter);
    expect(adapter.capturedRequests.single.data, {'secretKey': 'SECRET'});
    expect(result.response, 'SUCCESS');
    expect(result.device?.id, 'd-9');
    expect(result.device?.name, 'SN-001');
    expect(
      contract.coveredOperations(adapter.capturedRequests),
      contains('POST /api/customer/device/{deviceName}/claim'),
    );
  });

  test('claimDevice without secret sends an empty body', () async {
    adapter.on(
      'POST',
      '/api/customer/device/SN-001/claim',
      (_) => MockDioAdapter.jsonResponse({'response': 'CLAIMED'}),
    );

    final result = await repo.claimDevice('SN-001');

    contract.expectAllConform(adapter);
    expect(adapter.capturedRequests.single.data, isEmpty);
    expect(result.response, 'CLAIMED');
    expect(result.device, isNull);
  });

  test(
    'claimDevice URL-encodes a user-typed name with reserved characters',
    () async {
      // `/`, `#`, `?` and spaces must not change which route is called.
      const name = 'Boiler #1/A b?';
      const encoded = 'Boiler%20%231%2FA%20b%3F';
      adapter.on(
        'POST',
        '/api/customer/device/$encoded/claim',
        (_) => MockDioAdapter.jsonResponse({'response': 'SUCCESS'}),
      );

      final result = await repo.claimDevice(name);

      expect(result.response, 'SUCCESS');
      expect(
        adapter.capturedRequests.single.path,
        '/api/customer/device/$encoded/claim',
      );
      contract.expectAllConform(adapter);
    },
  );
}
