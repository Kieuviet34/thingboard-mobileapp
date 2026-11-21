import 'package:flutter_test/flutter_test.dart';
import 'package:thingsboard_democloud_app/core/api/client/tb_api_client.dart';
import 'package:thingsboard_democloud_app/core/api/repositories/notification_repository.dart';
import 'package:thingsboard_democloud_app/core/models/models.dart';

import '../../../../helpers/fake_secure_storage.dart';
import '../../../../helpers/mock_dio_adapter.dart';
import '../../../../helpers/openapi_contract.dart';

/// Contract test: every request `RestNotificationRepository` sends must exist in the
/// ThingsBoard 4.4.x OpenAPI, and every response shape must parse correctly.
void main() {
  late MockDioAdapter adapter;
  late RestNotificationRepository repo;
  final contract = OpenApiContract.load();

  const unreadJson = <String, dynamic>{
    'id': {'entityType': 'NOTIFICATION', 'id': 'n-1'},
    'recipientId': {'entityType': 'USER', 'id': 'u-1'},
    'type': 'ALARM',
    'deliveryMethod': 'WEB',
    'subject': 'Critical alarm',
    'text': 'High Temperature on Sensor 1',
    'status': 'SENT',
    'createdTime': 1700000000000,
    'info': {
      'type': 'ALARM',
      'alarmId': 'a-1',
      'alarmSeverity': 'CRITICAL',
      'alarmStatus': 'ACTIVE_UNACK',
    },
  };

  const readJson = <String, dynamic>{
    'id': {'entityType': 'NOTIFICATION', 'id': 'n-2'},
    'recipientId': {'entityType': 'USER', 'id': 'u-1'},
    'type': 'GENERAL',
    'deliveryMethod': 'WEB',
    'subject': 'Welcome',
    'text': 'Hello',
    'status': 'READ',
    'createdTime': 1700000001000,
  };

  Map<String, dynamic> page(List<Map<String, dynamic>> items) => {
    'data': items,
    'totalPages': 1,
    'totalElements': items.length,
    'hasNext': false,
  };

  setUp(() {
    adapter = MockDioAdapter();
    repo = RestNotificationRepository(
      client: TbApiClient(
        baseUrl: 'https://thingsboard.democloud.xyz/',
        storage: FakeSecureStorage(),
        httpClientAdapter: adapter,
      ),
    );
  });

  test(
    'getNotifications (unreadOnly + textSearch) sends spec-valid query and parses page',
    () async {
      adapter.on(
        'GET',
        '/api/notifications',
        (_) => MockDioAdapter.jsonResponse(page([unreadJson, readJson])),
      );

      final result = await repo.getNotifications(
        const PageQuery(textSearch: ' pump ', sortProperty: 'createdTime'),
        unreadOnly: true,
      );

      contract.expectAllConform(adapter);
      expect(adapter.capturedRequests.single.queryParameters, {
        'page': 0,
        'pageSize': 20,
        'textSearch': 'pump',
        'sortProperty': 'createdTime',
        'sortOrder': 'DESC',
        'unreadOnly': true,
      });
      expect(result.totalElements, 2);
      expect(result.hasNext, isFalse);

      final unread = result.data.first;
      expect(unread.id, 'n-1');
      expect(unread.subject, 'Critical alarm');
      expect(unread.text, 'High Temperature on Sensor 1');
      expect(unread.createdTime, 1700000000000);
      expect(unread.type, 'ALARM');
      expect(unread.deliveryMethod, 'WEB');
      expect(unread.isRead, isFalse);
      expect(unread.severity, AlarmSeverity.critical);
      expect(unread.info['alarmId'], 'a-1');

      final read = result.data[1];
      expect(read.id, 'n-2');
      expect(read.isRead, isTrue);
      expect(read.severity, isNull);

      expect(
        contract.coveredOperations(adapter.capturedRequests),
        contains('GET /api/notifications'),
      );
    },
  );

  test('getNotifications default sends unreadOnly=false', () async {
    adapter.on(
      'GET',
      '/api/notifications',
      (_) => MockDioAdapter.jsonResponse(page([readJson])),
    );

    await repo.getNotifications(const PageQuery());

    contract.expectAllConform(adapter);
    expect(adapter.capturedRequests.single.queryParameters, {
      'page': 0,
      'pageSize': 20,
      'sortProperty': 'createdTime',
      'sortOrder': 'DESC',
      'unreadOnly': false,
    });
  });

  test('getUnreadCount reads integer body', () async {
    adapter.on(
      'GET',
      '/api/notifications/unread/count',
      (_) => MockDioAdapter.jsonResponse(3),
    );

    expect(await repo.getUnreadCount(), 3);

    contract.expectAllConform(adapter);
    expect(adapter.capturedRequests.single.queryParameters, isEmpty);
    expect(
      contract.coveredOperations(adapter.capturedRequests),
      contains('GET /api/notifications/unread/count'),
    );
  });

  test(
    'markAsRead, markAllAsRead and deleteNotification use spec methods and paths',
    () async {
      adapter
        ..on(
          'PUT',
          '/api/notification/n-1/read',
          (_) => MockDioAdapter.emptyResponse(),
        )
        ..on(
          'PUT',
          '/api/notifications/read',
          (_) => MockDioAdapter.emptyResponse(),
        )
        ..on(
          'DELETE',
          '/api/notification/n-1',
          (_) => MockDioAdapter.emptyResponse(),
        );

      await repo.markAsRead('n-1');
      await repo.markAllAsRead();
      await repo.deleteNotification('n-1');

      contract.expectAllConform(adapter);
      expect(
        adapter.capturedRequests.map((r) => '${r.method} ${r.path}').toList(),
        [
          'PUT /api/notification/n-1/read',
          'PUT /api/notifications/read',
          'DELETE /api/notification/n-1',
        ],
      );
      expect(
        contract.coveredOperations(adapter.capturedRequests),
        containsAll(<String>[
          'PUT /api/notification/{id}/read',
          'PUT /api/notifications/read',
          'DELETE /api/notification/{id}',
        ]),
      );
    },
  );

  test('getNotificationSettings parses prefs', () async {
    adapter.on(
      'GET',
      '/api/notification/settings/user',
      (_) => MockDioAdapter.jsonResponse({
        'prefs': {
          'ALARM': {
            'enabled': true,
            'enabledDeliveryMethods': {'MOBILE_APP': true},
          },
        },
      }),
    );

    final settings = await repo.getNotificationSettings();

    contract.expectAllConform(adapter);
    expect(settings.prefs, {
      'ALARM': {
        'enabled': true,
        'enabledDeliveryMethods': {'MOBILE_APP': true},
      },
    });
    expect(
      contract.coveredOperations(adapter.capturedRequests),
      contains('GET /api/notification/settings/user'),
    );
  });

  test(
    'saveNotificationSettings posts {prefs} body and parses response',
    () async {
      adapter.on(
        'POST',
        '/api/notification/settings/user',
        (_) => MockDioAdapter.jsonResponse({
          'prefs': {
            'ALARM': {
              'enabled': false,
              'enabledDeliveryMethods': {'MOBILE_APP': false},
            },
          },
        }),
      );

      final saved = await repo.saveNotificationSettings(
        const TbUserNotificationSettings(
          prefs: {
            'ALARM': {
              'enabled': false,
              'enabledDeliveryMethods': {'MOBILE_APP': false},
            },
          },
        ),
      );

      contract.expectAllConform(adapter);
      final post = adapter.capturedRequests.single;
      expect(post.data, {
        'prefs': {
          'ALARM': {
            'enabled': false,
            'enabledDeliveryMethods': {'MOBILE_APP': false},
          },
        },
      });
      expect(saved.prefs, {
        'ALARM': {
          'enabled': false,
          'enabledDeliveryMethods': {'MOBILE_APP': false},
        },
      });
      expect(
        contract.coveredOperations(adapter.capturedRequests),
        contains('POST /api/notification/settings/user'),
      );
    },
  );

  test(
    'registerMobileSession and removeMobileSession send X-Mobile-Token and spec body',
    () async {
      adapter
        ..on(
          'POST',
          '/api/user/mobile/session',
          (_) => MockDioAdapter.emptyResponse(),
        )
        ..on(
          'DELETE',
          '/api/user/mobile/session',
          (_) => MockDioAdapter.emptyResponse(),
        );

      final before = DateTime.now().millisecondsSinceEpoch;
      await repo.registerMobileSession('fcm-token-abc');
      final after = DateTime.now().millisecondsSinceEpoch;
      await repo.removeMobileSession('fcm-token-abc');

      contract.expectAllConform(adapter);

      final post = adapter.capturedRequests.firstWhere(
        (r) => r.method == 'POST',
      );
      expect(post.headers['X-Mobile-Token'], 'fcm-token-abc');
      final body = post.data as Map<String, dynamic>;
      expect(body.keys.toList(), ['fcmTokenTimestamp']);
      final timestamp = body['fcmTokenTimestamp'];
      expect(timestamp, isA<int>());
      expect(timestamp as int, greaterThanOrEqualTo(before));
      expect(timestamp, lessThanOrEqualTo(after));

      final delete = adapter.capturedRequests.firstWhere(
        (r) => r.method == 'DELETE',
      );
      expect(delete.path, '/api/user/mobile/session');
      expect(delete.headers['X-Mobile-Token'], 'fcm-token-abc');
      expect(delete.data, isNull);

      expect(
        contract.coveredOperations(adapter.capturedRequests),
        containsAll(<String>[
          'POST /api/user/mobile/session',
          'DELETE /api/user/mobile/session',
        ]),
      );
    },
  );
}
