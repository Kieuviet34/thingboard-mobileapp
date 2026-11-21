import 'package:flutter_test/flutter_test.dart';
import 'package:thingsboard_democloud_app/core/api/client/tb_api_client.dart';
import 'package:thingsboard_democloud_app/core/api/repositories/rpc_repository.dart';
import 'package:thingsboard_democloud_app/core/models/models.dart';

import '../../../../helpers/fake_secure_storage.dart';
import '../../../../helpers/mock_dio_adapter.dart';
import '../../../../helpers/openapi_contract.dart';

/// Contract test: every request `RestRpcRepository` sends must exist in the
/// ThingsBoard 4.4.1PAAS OpenAPI, and every response shape must parse correctly.
void main() {
  late MockDioAdapter adapter;
  late RestRpcRepository repo;
  final contract = OpenApiContract.load();

  const rpcJson = <String, dynamic>{
    'id': {'entityType': 'RPC', 'id': 'rpc-1'},
    'createdTime': 1700000000000,
    'tenantId': {'entityType': 'TENANT', 'id': 't-1'},
    'deviceId': {'entityType': 'DEVICE', 'id': 'd-1'},
    'expirationTime': 1700000600000,
    'request': {
      'method': 'setTemp',
      'params': {'value': 22},
      'timeout': 5000,
      'persistent': true,
    },
    'response': {'status': 'OK'},
    'status': 'SUCCESSFUL',
    'additionalInfo': {},
  };

  setUp(() {
    adapter = MockDioAdapter();
    repo = RestRpcRepository(
      client: TbApiClient(
        baseUrl: 'https://thingsboard.democloud.xyz/',
        storage: FakeSecureStorage(),
        httpClientAdapter: adapter,
      ),
    );
  });

  test(
    'sendOneWayRpc POSTs oneway/{deviceId} with method, params, clamped timeout and persistent flag',
    () async {
      adapter.on(
        'POST',
        '/api/rpc/oneway/d-1',
        (_) => MockDioAdapter.emptyResponse(),
      );

      final plain = await repo.sendOneWayRpc(
        'd-1',
        const TbRpcRequest(
          method: 'setTemp',
          params: {'value': 22},
          timeoutMs: 1000,
        ),
      );
      final persistent = await repo.sendOneWayRpc(
        'd-1',
        const TbRpcRequest(
          method: 'setTemp',
          params: {'value': 22},
          timeoutMs: 15000,
          persistent: true,
          retries: 3,
        ),
      );

      expect(plain, isNull);
      expect(persistent, isNull);
      contract.expectAllConform(adapter);
      expect(adapter.capturedRequests[0].data, {
        'method': 'setTemp',
        'params': {'value': 22},
        'timeout': 5000,
        'persistent': false,
      });
      expect(adapter.capturedRequests[1].data, {
        'method': 'setTemp',
        'params': {'value': 22},
        'timeout': 15000,
        'persistent': true,
        'retries': 3,
      });
      expect(
        contract.coveredOperations(adapter.capturedRequests),
        contains('POST /api/rpc/oneway/{deviceId}'),
      );
    },
  );

  test(
    'sendTwoWayRpc returns the device map, wraps scalar replies and maps empty to null',
    () async {
      adapter
        ..enqueue(
          'POST',
          '/api/rpc/twoway/d-1',
          (_) => MockDioAdapter.jsonResponse({'status': 'OK', 'temp': 21.5}),
        )
        ..enqueue(
          'POST',
          '/api/rpc/twoway/d-1',
          (_) => MockDioAdapter.jsonResponse('pong'),
        )
        ..enqueue(
          'POST',
          '/api/rpc/twoway/d-1',
          (_) => MockDioAdapter.emptyResponse(),
        );

      final map = await repo.sendTwoWayRpc(
        'd-1',
        const TbRpcRequest(method: 'getStatus', timeoutMs: 15000),
      );
      final scalar = await repo.sendTwoWayRpc(
        'd-1',
        const TbRpcRequest(method: 'ping'),
      );
      final empty = await repo.sendTwoWayRpc(
        'd-1',
        const TbRpcRequest(method: 'reboot', timeoutMs: 1000),
      );

      expect(map, {'status': 'OK', 'temp': 21.5});
      expect(scalar, {'result': 'pong'});
      expect(empty, isNull);
      contract.expectAllConform(adapter);
      expect(adapter.capturedRequests[0].data, {
        'method': 'getStatus',
        'params': <String, dynamic>{},
        'timeout': 15000,
        'persistent': false,
      });
      expect(adapter.capturedRequests[1].data, {
        'method': 'ping',
        'params': <String, dynamic>{},
        'timeout': 10000,
        'persistent': false,
      });
      expect(adapter.capturedRequests[2].data, {
        'method': 'reboot',
        'params': <String, dynamic>{},
        'timeout': 5000,
        'persistent': false,
      });
      expect(
        contract.coveredOperations(adapter.capturedRequests),
        contains('POST /api/rpc/twoway/{deviceId}'),
      );
    },
  );

  test(
    'getPersistentRpcs sends page/pageSize/sort params and parses every status',
    () async {
      adapter.on(
        'GET',
        '/api/rpc/persistent/device/d-1',
        (_) => MockDioAdapter.jsonResponse({
          'data': [
            rpcJson,
            {
              ...rpcJson,
              'id': {'entityType': 'RPC', 'id': 'rpc-2'},
              'status': 'DELETED',
              'response': null,
            },
          ],
          'totalPages': 1,
          'totalElements': 2,
          'hasNext': false,
        }),
      );

      final page = await repo.getPersistentRpcs('d-1', const PageQuery());
      await repo.getPersistentRpcs(
        'd-1',
        const PageQuery(
          page: 2,
          pageSize: 5,
          textSearch: '  fail ',
          sortProperty: 'expirationTime',
          sortOrder: SortOrder.asc,
        ),
      );

      contract.expectAllConform(adapter);
      expect(adapter.capturedRequests[0].queryParameters, {
        'page': 0,
        'pageSize': 20,
        'sortProperty': 'createdTime',
        'sortOrder': 'DESC',
      });
      expect(adapter.capturedRequests[1].queryParameters, {
        'page': 2,
        'pageSize': 5,
        'textSearch': 'fail',
        'sortProperty': 'expirationTime',
        'sortOrder': 'ASC',
      });

      expect(page.totalPages, 1);
      expect(page.totalElements, 2);
      expect(page.hasNext, isFalse);
      final first = page.data[0];
      expect(first.id, 'rpc-1');
      expect(first.deviceId, 'd-1');
      expect(first.createdTime, 1700000000000);
      expect(first.expirationTime, 1700000600000);
      expect(first.status, RpcStatus.successful);
      expect(first.request['method'], 'setTemp');
      expect(first.response, {'status': 'OK'});
      expect(page.data[1].id, 'rpc-2');
      expect(page.data[1].status, RpcStatus.deleted);
      expect(page.data[1].response, isNull);
      expect(
        contract.coveredOperations(adapter.capturedRequests),
        contains('GET /api/rpc/persistent/device/{deviceId}'),
      );
    },
  );

  test(
    'deletePersistentRpc sends DELETE persistent/{rpcId} without body or query',
    () async {
      adapter.on(
        'DELETE',
        '/api/rpc/persistent/rpc-1',
        (_) => MockDioAdapter.emptyResponse(),
      );

      await repo.deletePersistentRpc('rpc-1');

      contract.expectAllConform(adapter);
      final request = adapter.capturedRequests.single;
      expect(request.path, '/api/rpc/persistent/rpc-1');
      expect(request.data, isNull);
      expect(request.queryParameters, isEmpty);
      expect(
        contract.coveredOperations(adapter.capturedRequests),
        contains('DELETE /api/rpc/persistent/{rpcId}'),
      );
    },
  );
}
