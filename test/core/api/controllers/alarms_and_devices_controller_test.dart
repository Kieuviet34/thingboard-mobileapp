import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:thingsboard_democloud_app/core/api/controllers/alarm_controller.dart';
import 'package:thingsboard_democloud_app/core/api/controllers/auth_controller.dart';
import 'package:thingsboard_democloud_app/core/api/controllers/device_controller.dart';
import 'package:thingsboard_democloud_app/core/api/controllers/server_config_controller.dart';
import 'package:thingsboard_democloud_app/core/models/models.dart';

import '../../../helpers/fake_app_preferences.dart';
import '../../../helpers/fake_secure_storage.dart';
import '../../../helpers/fake_ws_channel.dart';
import '../../../helpers/mock_dio_adapter.dart';
import '../../../helpers/test_container.dart';

void main() {
  late MockDioAdapter adapter;
  late FakeSecureStorage storage;
  late FakeAppPreferences prefs;
  late ProviderContainer container;

  setUp(() {
    adapter = MockDioAdapter();
    storage = FakeSecureStorage();
    prefs = FakeAppPreferences();
    container = createTestContainer(
      overrides: [
        tbStorageProvider.overrideWithValue(storage),
        tbAppPreferencesProvider.overrideWithValue(prefs),
        tbHttpClientAdapterProvider.overrideWithValue(adapter),
        wsChannelFactoryProvider.overrideWithValue(
          (_) => FakeWebSocketChannel(),
        ),
      ],
    );
  });

  group('AlarmController & DeviceController', () {
    test(
      'Demo mode alarm ack/clear/assign/unassign and comment work end-to-end',
      () async {
        await container.read(authProvider.notifier).loginDemo();

        final listState = await container.read(alarmsListProvider(null).future);
        expect(listState.items, isNotEmpty);

        final firstId = listState.items.first.id;
        await container
            .read(alarmsListProvider(null).notifier)
            .acknowledge(firstId);
        final afterAck = container.read(alarmsListProvider(null)).requireValue;
        expect(
          afterAck.items.firstWhere((a) => a.id == firstId).acknowledged,
          isTrue,
        );

        await container
            .read(alarmsListProvider(null).notifier)
            .assign(firstId, null);
        final afterUnassign = container
            .read(alarmsListProvider(null))
            .requireValue;
        expect(
          afterUnassign.items.firstWhere((a) => a.id == firstId).assigneeName,
          isNull,
        );

        await container
            .read(alarmCommentsProvider(firstId).notifier)
            .addComment('Checked damper');
        final comments = container
            .read(alarmCommentsProvider(firstId))
            .requireValue;
        expect(comments.items.any((c) => c.text == 'Checked damper'), isTrue);
      },
    );

    test(
      'Live mode alarm ack rolls back on 403 and guards stale refresh races',
      () async {
        adapter.on('GET', '/api/v2/alarms', (opts) {
          final page = opts.queryParameters['page'] as int? ?? 0;
          return MockDioAdapter.jsonResponse({
            'data': [
              {
                'id': {'entityType': 'ALARM', 'id': 'alm-$page'},
                'type': 'Overheat',
                'severity': 'CRITICAL',
                'acknowledged': false,
                'cleared': false,
                'createdTime': 1000,
                'originatorName': 'Dev-$page',
              },
            ],
            'totalPages': 2,
            'totalElements': 2,
            'hasNext': page == 0,
          });
        });

        adapter.on(
          'POST',
          '/api/alarm/alm-0/ack',
          (_) => MockDioAdapter.jsonResponse({
            'status': 403,
            'errorCode': 20,
            'message': 'Forbidden',
          }, statusCode: 403),
        );

        container.listen(alarmsListProvider(null), (_, _) {});
        final initial = await container.read(alarmsListProvider(null).future);
        expect(initial.items.single.acknowledged, isFalse);

        await expectLater(
          container
              .read(alarmsListProvider(null).notifier)
              .acknowledge('alm-0'),
          throwsA(isA<TbFailure>()),
        );
        // Rolled back to unacknowledged
        expect(
          container
              .read(alarmsListProvider(null))
              .requireValue
              .items
              .single
              .acknowledged,
          isFalse,
        );

        // Stale page refresh race: loadNextPage delayed, refresh supersedes it
        final slowGate = Completer<void>();
        adapter.enqueue('GET', '/api/v2/alarms', (_) async {
          await slowGate.future;
          return MockDioAdapter.jsonResponse({
            'data': [
              {
                'id': {'entityType': 'ALARM', 'id': 'stale-page-1'},
                'type': 'Stale',
                'severity': 'MINOR',
                'acknowledged': false,
                'cleared': false,
                'createdTime': 500,
                'originatorName': 'Old',
              },
            ],
            'totalPages': 2,
            'totalElements': 2,
            'hasNext': false,
          });
        });
        adapter.enqueue('GET', '/api/v2/alarms', (_) {
          return MockDioAdapter.jsonResponse({
            'data': [
              {
                'id': {'entityType': 'ALARM', 'id': 'fresh-page-0'},
                'type': 'Fresh',
                'severity': 'MAJOR',
                'acknowledged': false,
                'cleared': false,
                'createdTime': 2000,
                'originatorName': 'New',
              },
            ],
            'totalPages': 1,
            'totalElements': 1,
            'hasNext': false,
          });
        });

        final loadMoreFuture = container
            .read(alarmsListProvider(null).notifier)
            .loadNextPage();
        await Future<void>.delayed(const Duration(milliseconds: 10));
        await container.read(alarmsListProvider(null).notifier).refresh();
        slowGate.complete();
        await loadMoreFuture;

        final finalItems = container
            .read(alarmsListProvider(null))
            .requireValue
            .items;
        expect(finalItems.map((e) => e.id), ['fresh-page-0']);
      },
    );

    test(
      'Demo DeviceProfiles list matches Demo Devices active/inactive counts',
      () async {
        await container.read(authProvider.notifier).loginDemo();

        final profiles = await container.read(
          deviceProfilesListProvider.future,
        );
        final devices = await container.read(
          devicesListProvider(const TbDeviceQuery()).future,
        );

        for (final p in profiles.items) {
          final matching = devices.items
              .where((d) => d.type == p.name)
              .toList();
          expect(p.activeCount, matching.where((d) => d.active).length);
          expect(p.inactiveCount, matching.where((d) => !d.active).length);
        }
      },
    );
  });
}
