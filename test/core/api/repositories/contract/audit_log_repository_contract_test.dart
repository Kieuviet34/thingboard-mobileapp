import 'package:flutter_test/flutter_test.dart';
import 'package:thingsboard_democloud_app/core/api/client/tb_api_client.dart';
import 'package:thingsboard_democloud_app/core/api/repositories/audit_log_repository.dart';
import 'package:thingsboard_democloud_app/core/models/models.dart';

import '../../../../helpers/fake_secure_storage.dart';
import '../../../../helpers/mock_dio_adapter.dart';
import '../../../../helpers/openapi_contract.dart';

/// Contract test: every request `RestAuditLogRepository` sends must exist in the
/// ThingsBoard 4.4.x OpenAPI, and every response shape must parse correctly.
void main() {
  late MockDioAdapter adapter;
  late RestAuditLogRepository repo;
  final contract = OpenApiContract.load();

  const successJson = <String, dynamic>{
    'id': {'id': 'al-1'},
    'createdTime': 1700000000000,
    'tenantId': {'entityType': 'TENANT', 'id': 't-1'},
    'entityId': {'entityType': 'DEVICE', 'id': 'd-1'},
    'entityName': 'Sensor 1',
    'userId': {'entityType': 'USER', 'id': 'u-1'},
    'userName': 'ann@example.com',
    'actionType': 'UPDATED',
    'actionData': {
      'entity': {'name': 'Sensor 1'},
    },
    'actionStatus': 'SUCCESS',
  };

  const failureJson = <String, dynamic>{
    'id': {'id': 'al-2'},
    'createdTime': 1700000002000,
    'entityId': {'entityType': 'ALARM', 'id': 'a-1'},
    'entityName': 'High Temperature',
    'userId': {'entityType': 'USER', 'id': 'u-1'},
    'userName': 'ann@example.com',
    'actionType': 'ALARM_ACK',
    'actionStatus': 'FAILURE',
    'actionFailureDetails': 'Alarm is already acknowledged',
  };

  Map<String, dynamic> page(List<Map<String, dynamic>> items) => {
    'data': items,
    'totalPages': 1,
    'totalElements': items.length,
    'hasNext': false,
  };

  setUp(() {
    adapter = MockDioAdapter();
    repo = RestAuditLogRepository(
      client: TbApiClient(
        baseUrl: 'https://thingsboard.democloud.xyz/',
        storage: FakeSecureStorage(),
        httpClientAdapter: adapter,
      ),
    );
  });

  test(
    'tenant scope with all filters sends spec-valid query and parses page',
    () async {
      adapter.on(
        'GET',
        '/api/audit/logs',
        (_) => MockDioAdapter.jsonResponse(page([successJson, failureJson])),
      );

      final result = await repo.getAuditLogs(
        const PageQuery(),
        const TbAuditLogQuery(
          textSearch: ' Sensor 1 ',
          startTime: 1699999999000,
          endTime: 1700000001000,
          actionTypes: ['LOGIN', 'UPDATED'],
        ),
      );

      contract.expectAllConform(adapter);
      expect(adapter.capturedRequests.single.queryParameters, {
        'page': 0,
        'pageSize': 20,
        'sortProperty': 'createdTime',
        'sortOrder': 'DESC',
        'textSearch': 'Sensor 1',
        'startTime': 1699999999000,
        'endTime': 1700000001000,
        'actionTypes': 'LOGIN,UPDATED',
      });
      expect(result.totalElements, 2);
      expect(result.hasNext, isFalse);

      final success = result.data.first;
      expect(success.id, 'al-1');
      expect(success.entityName, 'Sensor 1');
      expect(success.entityType, EntityType.device);
      expect(success.actionType, 'UPDATED');
      expect(success.isSuccess, isTrue);
      expect(success.createdTime, 1700000000000);
      expect(success.userId, 'u-1');
      expect(success.userName, 'ann@example.com');
      expect(success.actionData, {
        'entity': {'name': 'Sensor 1'},
      });
      expect(success.failureDetails, isNull);

      final failure = result.data[1];
      expect(failure.id, 'al-2');
      expect(failure.entityType, EntityType.alarm);
      expect(failure.actionType, 'ALARM_ACK');
      expect(failure.isSuccess, isFalse);
      expect(failure.failureDetails, 'Alarm is already acknowledged');

      expect(
        contract.coveredOperations(adapter.capturedRequests),
        contains('GET /api/audit/logs'),
      );
    },
  );

  test('tenant scope omits blank textSearch and empty actionTypes', () async {
    adapter.on(
      'GET',
      '/api/audit/logs',
      (_) => MockDioAdapter.jsonResponse(page([successJson])),
    );

    await repo.getAuditLogs(
      const PageQuery(),
      const TbAuditLogQuery(textSearch: '   '),
    );

    contract.expectAllConform(adapter);
    expect(adapter.capturedRequests.single.queryParameters, {
      'page': 0,
      'pageSize': 20,
      'sortProperty': 'createdTime',
      'sortOrder': 'DESC',
    });
  });

  test(
    'entity scope uses /api/audit/logs/entity/{entityType}/{entityId}',
    () async {
      adapter.on(
        'GET',
        '/api/audit/logs/entity/ALARM/a-1',
        (_) => MockDioAdapter.jsonResponse(page([failureJson])),
      );

      final result = await repo.getAuditLogs(
        const PageQuery(page: 1, pageSize: 10),
        const TbAuditLogQuery(
          scope: AuditLogScope.entity,
          entityType: EntityType.alarm,
          targetId: 'a-1',
          startTime: 1700000000000,
        ),
      );

      contract.expectAllConform(adapter);
      expect(adapter.capturedRequests.single.queryParameters, {
        'page': 1,
        'pageSize': 10,
        'sortProperty': 'createdTime',
        'sortOrder': 'DESC',
        'startTime': 1700000000000,
      });
      expect(result.data.single.id, 'al-2');
      expect(
        contract.coveredOperations(adapter.capturedRequests),
        contains('GET /api/audit/logs/entity/{entityType}/{entityId}'),
      );
    },
  );

  test('entity scope without entityType defaults to DEVICE', () async {
    adapter.on(
      'GET',
      '/api/audit/logs/entity/DEVICE/d-1',
      (_) => MockDioAdapter.jsonResponse(page([successJson])),
    );

    final result = await repo.getAuditLogs(
      const PageQuery(),
      const TbAuditLogQuery(scope: AuditLogScope.entity, targetId: 'd-1'),
    );

    contract.expectAllConform(adapter);
    expect(
      adapter.capturedRequests.single.path,
      '/api/audit/logs/entity/DEVICE/d-1',
    );
    expect(result.data.single.entityType, EntityType.device);
  });

  test(
    'user scope uses /api/audit/logs/user/{userId} with action filter',
    () async {
      adapter.on(
        'GET',
        '/api/audit/logs/user/u-1',
        (_) => MockDioAdapter.jsonResponse(page([successJson, failureJson])),
      );

      final result = await repo.getAuditLogs(
        const PageQuery(),
        const TbAuditLogQuery(
          scope: AuditLogScope.user,
          targetId: 'u-1',
          actionTypes: ['LOGIN'],
        ),
      );

      contract.expectAllConform(adapter);
      expect(adapter.capturedRequests.single.queryParameters, {
        'page': 0,
        'pageSize': 20,
        'sortProperty': 'createdTime',
        'sortOrder': 'DESC',
        'actionTypes': 'LOGIN',
      });
      expect(result.data.map((l) => l.id), ['al-1', 'al-2']);
      expect(
        contract.coveredOperations(adapter.capturedRequests),
        contains('GET /api/audit/logs/user/{userId}'),
      );
    },
  );

  test('customer scope uses /api/audit/logs/customer/{customerId}', () async {
    adapter.on(
      'GET',
      '/api/audit/logs/customer/c-1',
      (_) => MockDioAdapter.jsonResponse(page([successJson])),
    );

    final result = await repo.getAuditLogs(
      const PageQuery(textSearch: 'sensor'),
      const TbAuditLogQuery(
        scope: AuditLogScope.customer,
        targetId: 'c-1',
        endTime: 1700000001000,
      ),
    );

    contract.expectAllConform(adapter);
    expect(adapter.capturedRequests.single.queryParameters, {
      'page': 0,
      'pageSize': 20,
      'textSearch': 'sensor',
      'sortProperty': 'createdTime',
      'sortOrder': 'DESC',
      'endTime': 1700000001000,
    });
    expect(result.data.single.userName, 'ann@example.com');
    expect(
      contract.coveredOperations(adapter.capturedRequests),
      contains('GET /api/audit/logs/customer/{customerId}'),
    );
  });

  test('403 from the audit endpoint surfaces as permissionDenied', () async {
    adapter.on(
      'GET',
      '/api/audit/logs',
      (_) => MockDioAdapter.jsonResponse({
        'status': 403,
        'message': 'Permission denied',
      }, statusCode: 403),
    );

    await expectLater(
      repo.getAuditLogs(const PageQuery(), const TbAuditLogQuery()),
      throwsA(
        isA<TbFailure>().having(
          (e) => e.type,
          'type',
          TbFailureType.permissionDenied,
        ),
      ),
    );
    contract.expectAllConform(adapter);
  });
}
