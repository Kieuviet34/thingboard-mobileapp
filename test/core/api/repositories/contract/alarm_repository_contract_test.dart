import 'package:flutter_test/flutter_test.dart';
import 'package:thingsboard_democloud_app/core/api/client/tb_api_client.dart';
import 'package:thingsboard_democloud_app/core/api/repositories/alarm_repository.dart';
import 'package:thingsboard_democloud_app/core/models/models.dart';

import '../../../../helpers/fake_secure_storage.dart';
import '../../../../helpers/mock_dio_adapter.dart';
import '../../../../helpers/openapi_contract.dart';

/// Contract test: every request `RestAlarmRepository` sends must exist in the
/// ThingsBoard 4.4.x OpenAPI, and every response shape must parse correctly.
void main() {
  late MockDioAdapter adapter;
  late RestAlarmRepository repo;
  final contract = OpenApiContract.load();

  const alarmJson = <String, dynamic>{
    'id': {'entityType': 'ALARM', 'id': 'a-1'},
    'createdTime': 1700000000000,
    'name': 'High Temperature',
    'type': 'High Temperature',
    'severity': 'CRITICAL',
    'status': 'ACTIVE_UNACK',
    'acknowledged': false,
    'cleared': false,
    'originator': {'entityType': 'DEVICE', 'id': 'd-1'},
    'originatorName': 'Sensor 1',
    'assignee': {
      'id': {'entityType': 'USER', 'id': 'u-1'},
      'firstName': 'Ann',
      'lastName': 'Lee',
      'email': 'ann@example.com',
    },
    'assigneeId': {'entityType': 'USER', 'id': 'u-1'},
  };

  Map<String, dynamic> page(List<Map<String, dynamic>> items) => {
    'data': items,
    'totalPages': 1,
    'totalElements': items.length,
    'hasNext': false,
  };

  setUp(() {
    adapter = MockDioAdapter();
    repo = RestAlarmRepository(
      client: TbApiClient(
        baseUrl: 'https://thingsboard.democloud.xyz/',
        storage: FakeSecureStorage(),
        httpClientAdapter: adapter,
      ),
    );
  });

  test(
    'getAlarms (all filters) sends spec-valid query and parses page',
    () async {
      adapter.on(
        'GET',
        '/api/v2/alarms',
        (_) => MockDioAdapter.jsonResponse(page([alarmJson])),
      );

      final result = await repo.getAlarms(
        const PageQuery(textSearch: ' temp '),
        const TbAlarmFilter(
          textSearch: 'temp',
          statusList: {AlarmSearchStatus.active, AlarmSearchStatus.unack},
          severityList: {AlarmSeverity.critical, AlarmSeverity.major},
          typeList: {'High Temperature'},
          assigneeId: 'u-1',
          startTime: 1,
          endTime: 2,
        ),
      );

      contract.expectAllConform(adapter);
      final alarm = result.data.single;
      expect(alarm.id, 'a-1');
      expect(alarm.severity, AlarmSeverity.critical);
      expect(alarm.originator?.id, 'd-1');
      expect(alarm.assigneeName, 'Ann Lee');
      expect(alarm.assigneeId, 'u-1');
      expect(alarm.cleared, isFalse);
      expect(result.hasNext, isFalse);
    },
  );

  test('getAlarms for an originator uses /api/v2/alarm/{type}/{id}', () async {
    adapter.on(
      'GET',
      '/api/v2/alarm/DEVICE/d-1',
      (_) => MockDioAdapter.jsonResponse(page([alarmJson])),
    );

    final result = await repo.getAlarms(
      const PageQuery(),
      const TbAlarmFilter(
        originatorId: EntityId(entityType: EntityType.device, id: 'd-1'),
      ),
    );

    expect(result.data, hasLength(1));
    contract.expectAllConform(adapter);
  });

  test(
    'ack / clear / assign / unassign / info use spec methods and paths',
    () async {
      adapter
        ..on(
          'GET',
          '/api/alarm/info/a-1',
          (_) => MockDioAdapter.jsonResponse(alarmJson),
        )
        ..on(
          'POST',
          '/api/alarm/a-1/ack',
          (_) =>
              MockDioAdapter.jsonResponse({...alarmJson, 'acknowledged': true}),
        )
        ..on(
          'POST',
          '/api/alarm/a-1/clear',
          (_) => MockDioAdapter.jsonResponse({...alarmJson, 'cleared': true}),
        )
        ..on(
          'POST',
          '/api/alarm/a-1/assign/u-9',
          (_) => MockDioAdapter.jsonResponse(alarmJson),
        )
        ..on(
          'DELETE',
          '/api/alarm/a-1/assign',
          (_) =>
              MockDioAdapter.jsonResponse({...alarmJson}..remove('assignee')),
        );

      expect((await repo.getAlarmInfo('a-1')).id, 'a-1');
      expect((await repo.ackAlarm('a-1')).acknowledged, isTrue);
      expect((await repo.clearAlarm('a-1')).cleared, isTrue);
      expect((await repo.assignAlarm('a-1', 'u-9')).id, 'a-1');
      expect((await repo.unassignAlarm('a-1')).assigneeName, isNull);

      contract.expectAllConform(adapter);
      expect(
        contract.coveredOperations(adapter.capturedRequests),
        containsAll(<String>[
          'GET /api/alarm/info/{alarmId}',
          'POST /api/alarm/{alarmId}/ack',
          'POST /api/alarm/{alarmId}/clear',
          'POST /api/alarm/{alarmId}/assign/{assigneeId}',
          'DELETE /api/alarm/{alarmId}/assign',
        ]),
      );
    },
  );

  test('assignees and comments (list + add) conform and parse', () async {
    adapter
      ..on(
        'GET',
        '/api/users/assign/a-1',
        (_) => MockDioAdapter.jsonResponse(
          page([
            {
              'id': {'entityType': 'USER', 'id': 'u-1'},
              'email': 'ann@example.com',
              'firstName': 'Ann',
              'lastName': 'Lee',
            },
          ]),
        ),
      )
      ..on(
        'GET',
        '/api/alarm/a-1/comment',
        (_) => MockDioAdapter.jsonResponse(
          page([
            {
              'id': {'id': 'c-1'},
              'alarmId': {'entityType': 'ALARM', 'id': 'a-1'},
              'type': 'OTHER',
              'comment': {'text': 'checked'},
              'createdTime': 1700000000001,
              'firstName': 'Ann',
              'lastName': 'Lee',
            },
          ]),
        ),
      )
      ..on(
        'POST',
        '/api/alarm/a-1/comment',
        (_) => MockDioAdapter.jsonResponse({
          'id': {'id': 'c-2'},
          'alarmId': {'entityType': 'ALARM', 'id': 'a-1'},
          'type': 'OTHER',
          'comment': {'text': 'on it'},
          'createdTime': 1700000000002,
        }),
      );

    final assignees = await repo.getAssignees('a-1', const PageQuery());
    expect(assignees.data.single.displayName, 'Ann Lee');

    final comments = await repo.getComments('a-1', const PageQuery());
    expect(comments.data.single.text, 'checked');
    expect(comments.data.single.authorName, 'Ann Lee');

    final added = await repo.addComment('a-1', 'on it');
    expect(added.text, 'on it');

    // The body the app sends must be what ThingsBoard expects.
    final post = adapter.capturedRequests.firstWhere((r) => r.method == 'POST');
    expect(post.data, {
      'comment': {'text': 'on it'},
    });
    contract.expectAllConform(adapter);
  });
}
