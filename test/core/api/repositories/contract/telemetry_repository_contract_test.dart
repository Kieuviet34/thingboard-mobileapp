import 'package:flutter_test/flutter_test.dart';
import 'package:thingsboard_democloud_app/core/api/client/tb_api_client.dart';
import 'package:thingsboard_democloud_app/core/api/repositories/telemetry_repository.dart';
import 'package:thingsboard_democloud_app/core/models/models.dart';

import '../../../../helpers/fake_secure_storage.dart';
import '../../../../helpers/mock_dio_adapter.dart';
import '../../../../helpers/openapi_contract.dart';

/// Contract test: every request `RestTelemetryRepository` sends must exist in the
/// ThingsBoard 4.4.1PAAS OpenAPI, and every response shape must parse correctly.
void main() {
  late MockDioAdapter adapter;
  late RestTelemetryRepository repo;
  final contract = OpenApiContract.load();

  const device = EntityId(entityType: EntityType.device, id: 'd-1');
  const devicePath = '/api/plugins/telemetry/DEVICE/d-1';
  const latestPath = '$devicePath/values/timeseries';
  const historyPath = '$devicePath/values/timeseries/history';

  const historyQuery = TbTsHistoryQuery(
    entityId: device,
    keys: ['temperature'],
    startTs: 1700000000000,
    endTs: 1700003600000,
    intervalMs: 60000,
    limit: 10,
    agg: TsAggregation.avg,
  );

  setUp(() {
    adapter = MockDioAdapter();
    repo = RestTelemetryRepository(
      client: TbApiClient(
        baseUrl: 'https://thingsboard.democloud.xyz/',
        storage: FakeSecureStorage(),
        httpClientAdapter: adapter,
      ),
    );
  });

  test(
    'getAttributes reads values/attributes/{scope} for every scope and parses entries',
    () async {
      for (final scope in TbAttributeScope.values) {
        adapter.on(
          'GET',
          '$devicePath/values/attributes/${scope.wireValue}',
          (_) => MockDioAdapter.jsonResponse([
            {'lastUpdateTs': 1700000000000, 'key': 'fw', 'value': '1.2.3'},
          ]),
        );
      }

      for (final scope in TbAttributeScope.values) {
        final entries = await repo.getAttributes(device, scope);
        expect(entries.single.key, 'fw');
        expect(entries.single.displayValue, '1.2.3');
        expect(entries.single.lastUpdateTs, 1700000000000);
        expect(entries.single.scope, scope);
      }

      contract.expectAllConform(adapter);
      expect(
        contract.coveredOperations(adapter.capturedRequests),
        contains(
          'GET /api/plugins/telemetry/{entityType}/{entityId}/values/attributes/{scope}',
        ),
      );
    },
  );

  test(
    'saveAttributes POSTs attributes/{scope} with the attribute map as body',
    () async {
      adapter
        ..on(
          'POST',
          '$devicePath/attributes/SHARED_SCOPE',
          (_) => MockDioAdapter.emptyResponse(),
        )
        ..on(
          'POST',
          '$devicePath/attributes/SERVER_SCOPE',
          (_) => MockDioAdapter.emptyResponse(),
        );

      await repo.saveAttributes(device, TbAttributeScope.sharedScope, {
        'targetTemp': 22,
        'mode': 'auto',
      });
      await repo.saveAttributes(device, TbAttributeScope.serverScope, {
        'owner': 'ann',
      });

      contract.expectAllConform(adapter);
      expect(adapter.capturedRequests[0].data, {
        'targetTemp': 22,
        'mode': 'auto',
      });
      expect(adapter.capturedRequests[1].data, {'owner': 'ann'});
      expect(
        contract.coveredOperations(adapter.capturedRequests),
        contains(
          'POST /api/plugins/telemetry/{entityType}/{entityId}/attributes/{scope}',
        ),
      );
    },
  );

  test(
    'saveAttributes refuses CLIENT_SCOPE without sending a request',
    () async {
      // The spec only allows SERVER_SCOPE|SHARED_SCOPE; client attributes belong
      // to the device. Same failure the Demo repository raises.
      adapter.on(
        'POST',
        '$devicePath/attributes/CLIENT_SCOPE',
        (_) => MockDioAdapter.emptyResponse(),
      );

      await expectLater(
        repo.saveAttributes(device, TbAttributeScope.clientScope, {'a': 1}),
        throwsA(
          isA<TbFailure>().having(
            (f) => f.type,
            'type',
            TbFailureType.validation,
          ),
        ),
      );
      expect(adapter.capturedRequests, isEmpty);
    },
  );

  test(
    'deleteAttributes sends DELETE {scope} with keys as a comma-separated query',
    () async {
      adapter
        ..on(
          'DELETE',
          '$devicePath/CLIENT_SCOPE',
          (_) => MockDioAdapter.emptyResponse(),
        )
        ..on(
          'DELETE',
          '$devicePath/SHARED_SCOPE',
          (_) => MockDioAdapter.emptyResponse(),
        );

      await repo.deleteAttributes(device, TbAttributeScope.clientScope, [
        'fw',
        'alarmLimit',
      ]);
      await repo.deleteAttributes(device, TbAttributeScope.sharedScope, [
        'owner',
      ]);

      contract.expectAllConform(adapter);
      expect(adapter.capturedRequests[0].queryParameters, {
        'keys': 'fw,alarmLimit',
      });
      expect(adapter.capturedRequests[1].queryParameters, {'keys': 'owner'});
      expect(
        contract.coveredOperations(adapter.capturedRequests),
        contains(
          'DELETE /api/plugins/telemetry/{entityType}/{entityId}/{scope}',
        ),
      );
    },
  );

  test(
    'getLatestTimeseries sends useStrictDataTypes and keeps the first point per key',
    () async {
      adapter.on(
        'GET',
        latestPath,
        (_) => MockDioAdapter.jsonResponse({
          'temperature': [
            {'ts': 1700000000000, 'value': 24.6},
          ],
          'humidity': [
            {'ts': 1700000000500, 'value': '55'},
          ],
          'emptyKey': [],
        }),
      );

      final withKeys = await repo.getLatestTimeseries(
        device,
        keys: ['temperature', 'humidity'],
      );
      final all = await repo.getLatestTimeseries(device);

      contract.expectAllConform(adapter);
      expect(adapter.capturedRequests[0].queryParameters, {
        'keys': 'temperature,humidity',
        'useStrictDataTypes': true,
      });
      expect(adapter.capturedRequests[1].queryParameters, {
        'useStrictDataTypes': true,
      });

      expect(withKeys.keys, unorderedEquals(['temperature', 'humidity']));
      expect(withKeys['temperature']!.ts, 1700000000000);
      expect(withKeys['temperature']!.rawValue, 24.6);
      expect(withKeys['temperature']!.numericValue, 24.6);
      expect(withKeys['humidity']!.rawValue, '55');
      expect(withKeys['humidity']!.numericValue, 55);
      expect(all.keys, unorderedEquals(['temperature', 'humidity']));
      expect(
        contract.coveredOperations(adapter.capturedRequests),
        contains(
          'GET /api/plugins/telemetry/{entityType}/{entityId}/values/timeseries',
        ),
      );
    },
  );

  test(
    'getTimeseriesHistory falls back to values/timeseries only on HTTP 404',
    () async {
      adapter
        ..enqueue(
          'GET',
          historyPath,
          (_) => MockDioAdapter.jsonResponse({'status': 404}, statusCode: 404),
        )
        ..on(
          'GET',
          latestPath,
          (_) => MockDioAdapter.jsonResponse({
            'temperature': [
              {'ts': 1700000000000, 'value': 23.4},
              {'ts': 1700000060000, 'value': '23.5'},
            ],
          }),
        );

      final history = await repo.getTimeseriesHistory(historyQuery);

      expect(adapter.capturedRequests.map((r) => r.path), [
        historyPath,
        latestPath,
      ]);
      expect(adapter.capturedRequests[1].queryParameters, {
        'keys': 'temperature',
        'startTs': 1700000000000,
        'endTs': 1700003600000,
        'interval': 60000,
        'limit': 10,
        'agg': 'AVG',
        'orderBy': 'ASC',
        'useStrictDataTypes': true,
      });
      expect(history['temperature']!.map((p) => p.numericValue), [23.4, 23.5]);

      contract.expectAllConform(adapter);
      expect(
        contract.coveredOperations(adapter.capturedRequests),
        contains(
          'GET /api/plugins/telemetry/{entityType}/{entityId}/values/timeseries',
        ),
      );
    },
  );

  for (final status in [400, 403]) {
    test(
      'getTimeseriesHistory does NOT fall back to values/timeseries on HTTP $status',
      () async {
        adapter.enqueue(
          'GET',
          historyPath,
          (_) => MockDioAdapter.jsonResponse({
            'status': status,
          }, statusCode: status),
        );

        TbFailure? failure;
        try {
          await repo.getTimeseriesHistory(historyQuery);
        } on TbFailure catch (e) {
          failure = e;
        }

        expect(failure, isNotNull);
        expect(
          failure!.type,
          status == 400
              ? TbFailureType.validation
              : TbFailureType.permissionDenied,
        );
        expect(adapter.capturedRequests.map((r) => r.path), [historyPath]);
        contract.expectAllConform(adapter);
      },
    );
  }

  test(
    'getTimeseriesHistory with no keys, no interval and agg NONE sends defaults and parses',
    () async {
      adapter.on(
        'GET',
        historyPath,
        (_) => MockDioAdapter.jsonResponse({
          'humidity': [
            {'ts': 1700000000000, 'value': '55'},
          ],
        }),
      );

      final result = await repo.getTimeseriesHistory(
        const TbTsHistoryQuery(
          entityId: device,
          keys: [],
          startTs: 1,
          endTs: 2,
        ),
      );

      expect(adapter.capturedRequests.single.queryParameters, {
        'startTs': 1,
        'endTs': 2,
        'limit': 100,
        'agg': 'NONE',
        'orderBy': 'ASC',
        'useStrictDataTypes': true,
      });
      expect(result['humidity']!.single.numericValue, 55);

      contract.expectAllConform(adapter);
    },
  );
}
