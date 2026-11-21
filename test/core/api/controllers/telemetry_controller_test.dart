import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:thingsboard_democloud_app/core/api/client/tb_secure_storage.dart';
import 'package:thingsboard_democloud_app/core/api/controllers/auth_controller.dart';
import 'package:thingsboard_democloud_app/core/api/controllers/server_config_controller.dart';
import 'package:thingsboard_democloud_app/core/api/controllers/telemetry_controller.dart';
import 'package:thingsboard_democloud_app/core/models/entity_id.dart';
import 'package:thingsboard_democloud_app/core/models/tb_failure.dart';
import 'package:thingsboard_democloud_app/core/models/telemetry_models.dart';

import '../../../helpers/fake_app_preferences.dart';
import '../../../helpers/fake_secure_storage.dart';
import '../../../helpers/fake_ws_channel.dart';
import '../../../helpers/mock_dio_adapter.dart';
import '../../../helpers/openapi_contract.dart';
import '../../../helpers/test_container.dart';

const _device = EntityId(entityType: EntityType.device, id: 'dev-1');
const _attrsArg = (id: _device, scope: TbAttributeScope.sharedScope);
const _attrsReadPath =
    '/api/plugins/telemetry/DEVICE/dev-1/values/attributes/SHARED_SCOPE';
const _attrsWritePath =
    '/api/plugins/telemetry/DEVICE/dev-1/attributes/SHARED_SCOPE';
const _attrsDeletePath = '/api/plugins/telemetry/DEVICE/dev-1/SHARED_SCOPE';
const _latestPath = '/api/plugins/telemetry/DEVICE/dev-1/values/timeseries';
const _historyPath =
    '/api/plugins/telemetry/DEVICE/dev-1/values/timeseries/history';
const _oneDayMs = 24 * 60 * 60 * 1000;

void main() {
  final contract = OpenApiContract.load();
  late MockDioAdapter adapter;
  late FakeSecureStorage storage;
  late List<FakeWebSocketChannel> wsChannels;
  late ProviderContainer container;

  setUp(() {
    adapter = MockDioAdapter();
    storage = FakeSecureStorage(
      initial: {
        TbStorageKeys.accessToken: 'live-jwt',
        TbStorageKeys.refreshToken: 'live-refresh',
      },
    );
    wsChannels = [];
    container = createTestContainer(
      overrides: [
        tbStorageProvider.overrideWithValue(storage),
        tbAppPreferencesProvider.overrideWithValue(FakeAppPreferences()),
        tbHttpClientAdapterProvider.overrideWithValue(adapter),
        wsChannelFactoryProvider.overrideWithValue((_) {
          final channel = FakeWebSocketChannel();
          wsChannels.add(channel);
          return channel;
        }),
      ],
    );
  });

  /// Returns the cmdId of the first sent command with [type], waiting briefly.
  Future<int> awaitSentCmdId(String type) async {
    for (var i = 0; i < 200; i++) {
      for (final channel in wsChannels) {
        for (final frame in channel.decodedSentFrames) {
          final cmds = (frame['cmds'] as List<dynamic>?) ?? const [];
          for (final cmd in cmds.whereType<Map<String, dynamic>>()) {
            if (cmd['type'] == type) {
              return (cmd['cmdId'] as num).toInt();
            }
          }
        }
      }
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    fail('WebSocket command $type was never sent');
  }

  group('EntityAttributesNotifier (live HTTP)', () {
    test('reads attributes for the requested scope', () async {
      adapter.on(
        'GET',
        _attrsReadPath,
        (_) => MockDioAdapter.jsonResponse([
          {'key': 'targetTemp', 'value': 22.0, 'lastUpdateTs': 1000},
          {'key': 'fanMode', 'value': 'AUTO', 'lastUpdateTs': 2000},
        ]),
      );
      container.listen(entityAttributesProvider(_attrsArg), (_, _) {});

      final attrs = await container.read(
        entityAttributesProvider(_attrsArg).future,
      );

      expect(attrs.map((a) => a.key), ['targetTemp', 'fanMode']);
      expect(attrs.first.value, 22.0);
      expect(attrs.last.lastUpdateTs, 2000);
      expect(
        attrs.every((a) => a.scope == TbAttributeScope.sharedScope),
        isTrue,
      );
      contract.expectAllConform(adapter);
    });

    test('saveAttributes posts the body and refetches the scope', () async {
      final store = <String, dynamic>{'targetTemp': 22.0, 'fanMode': 'AUTO'};
      adapter.on(
        'GET',
        _attrsReadPath,
        (_) => MockDioAdapter.jsonResponse([
          for (final e in store.entries)
            {'key': e.key, 'value': e.value, 'lastUpdateTs': 1000},
        ]),
      );
      adapter.on('POST', _attrsWritePath, (opts) {
        store.addAll(Map<String, dynamic>.from(opts.data as Map));
        return MockDioAdapter.emptyResponse();
      });
      container.listen(entityAttributesProvider(_attrsArg), (_, _) {});
      await container.read(entityAttributesProvider(_attrsArg).future);

      await container
          .read(entityAttributesProvider(_attrsArg).notifier)
          .saveAttributes({'targetTemp': 24.0});

      final post = adapter.capturedRequests.singleWhere(
        (r) => r.method == 'POST',
      );
      expect(post.data, {'targetTemp': 24.0});
      final attrs = await container.read(
        entityAttributesProvider(_attrsArg).future,
      );
      expect(attrs.firstWhere((a) => a.key == 'targetTemp').value, 24.0);
      expect(attrs.map((a) => a.key), ['targetTemp', 'fanMode']);
      expect(
        adapter.capturedRequests.where((r) => r.method == 'GET'),
        hasLength(2),
        reason: 'saving must invalidate and refetch the attribute scope',
      );
      contract.expectAllConform(adapter);
    });

    test('deleteAttributes sends the keys and refetches the scope', () async {
      final store = <String, dynamic>{'targetTemp': 22.0, 'fanMode': 'AUTO'};
      adapter.on(
        'GET',
        _attrsReadPath,
        (_) => MockDioAdapter.jsonResponse([
          for (final e in store.entries)
            {'key': e.key, 'value': e.value, 'lastUpdateTs': 1000},
        ]),
      );
      adapter.on('DELETE', _attrsDeletePath, (opts) {
        final keys = (opts.queryParameters['keys'] as String).split(',');
        store.removeWhere((key, _) => keys.contains(key));
        return MockDioAdapter.emptyResponse();
      });
      container.listen(entityAttributesProvider(_attrsArg), (_, _) {});
      await container.read(entityAttributesProvider(_attrsArg).future);

      await container
          .read(entityAttributesProvider(_attrsArg).notifier)
          .deleteAttributes(['fanMode']);

      final delete = adapter.capturedRequests.singleWhere(
        (r) => r.method == 'DELETE',
      );
      expect(delete.queryParameters['keys'], 'fanMode');
      final attrs = await container.read(
        entityAttributesProvider(_attrsArg).future,
      );
      expect(attrs.map((a) => a.key), ['targetTemp']);
      contract.expectAllConform(adapter);
    });

    test('a rejected save surfaces the failure and does not refetch', () async {
      adapter.on(
        'GET',
        _attrsReadPath,
        (_) => MockDioAdapter.jsonResponse([
          {'key': 'targetTemp', 'value': 22.0, 'lastUpdateTs': 1000},
        ]),
      );
      adapter.enqueue(
        'POST',
        _attrsWritePath,
        (_) => MockDioAdapter.jsonResponse({
          'status': 403,
          'errorCode': 20,
          'message': 'Forbidden',
        }, statusCode: 403),
      );
      container.listen(entityAttributesProvider(_attrsArg), (_, _) {});
      await container.read(entityAttributesProvider(_attrsArg).future);

      await expectLater(
        container
            .read(entityAttributesProvider(_attrsArg).notifier)
            .saveAttributes({'targetTemp': 99.0}),
        throwsA(
          isA<TbFailure>().having(
            (f) => f.type,
            'type',
            TbFailureType.permissionDenied,
          ),
        ),
      );
      final attrs = container
          .read(entityAttributesProvider(_attrsArg))
          .requireValue;
      expect(attrs.single.value, 22.0);
      expect(
        adapter.capturedRequests.where((r) => r.method == 'GET'),
        hasLength(1),
      );
    });
  });

  group('Telemetry reads (live HTTP)', () {
    test('latest values keep only keys that have a point', () async {
      adapter.on(
        'GET',
        _latestPath,
        (_) => MockDioAdapter.jsonResponse({
          'temperature': [
            {'ts': 1700000000000, 'value': 21.5},
          ],
          'humidity': <dynamic>[],
          'status': [
            {'ts': 1700000000001, 'value': 'OK'},
          ],
        }),
      );
      container.listen(entityLatestTelemetryProvider(_device), (_, _) {});

      final latest = await container.read(
        entityLatestTelemetryProvider(_device).future,
      );

      expect(latest.keys, unorderedEquals(['temperature', 'status']));
      expect(latest['temperature']!.numericValue, 21.5);
      expect(latest['temperature']!.ts, 1700000000000);
      expect(latest['status']!.rawValue, 'OK');
      expect(latest['status']!.numericValue, isNull);
      final request = adapter.capturedRequests.single;
      expect(request.queryParameters['useStrictDataTypes'], true);
      expect(request.queryParameters.containsKey('keys'), isFalse);
      contract.expectAllConform(adapter);
    });

    test(
      'history defaults to the last 24 hours with ASC, unaggregated points',
      () async {
        adapter.on(
          'GET',
          _historyPath,
          (_) => MockDioAdapter.jsonResponse({
            'temperature': [
              {'ts': 100, 'value': 20.0},
              {'ts': 200, 'value': 21.0},
            ],
          }),
        );
        container.listen(entityTelemetryHistoryProvider(_device), (_, _) {});

        final history = await container.read(
          entityTelemetryHistoryProvider(_device).future,
        );

        expect(history['temperature']!.map((p) => p.numericValue), [
          20.0,
          21.0,
        ]);
        final query = adapter.capturedRequests.single.queryParameters;
        expect(query['agg'], 'NONE');
        expect(query['orderBy'], 'ASC');
        expect(query['limit'], 100);
        expect(query['useStrictDataTypes'], true);
        expect(query.containsKey('keys'), isFalse);
        expect(query.containsKey('interval'), isFalse);
        expect((query['endTs'] as int) - (query['startTs'] as int), _oneDayMs);
        contract.expectAllConform(adapter);
      },
    );

    test('loadRange forwards keys, interval, limit and aggregation', () async {
      adapter.on(
        'GET',
        _historyPath,
        (_) => MockDioAdapter.jsonResponse({
          'temperature': [
            {'ts': 1000, 'value': 20.0},
          ],
          'humidity': [
            {'ts': 1000, 'value': 46.0},
          ],
        }),
      );
      container.listen(entityTelemetryHistoryProvider(_device), (_, _) {});
      await container.read(entityTelemetryHistoryProvider(_device).future);

      await container
          .read(entityTelemetryHistoryProvider(_device).notifier)
          .loadRange(
            const TbTsHistoryQuery(
              entityId: _device,
              keys: ['temperature', 'humidity'],
              startTs: 1000,
              endTs: 5000,
              intervalMs: 1000,
              limit: 4,
              agg: TsAggregation.avg,
            ),
          );

      final query = adapter.capturedRequests.last.queryParameters;
      expect(query['keys'], 'temperature,humidity');
      expect(query['startTs'], 1000);
      expect(query['endTs'], 5000);
      expect(query['interval'], 1000);
      expect(query['limit'], 4);
      expect(query['agg'], 'AVG');
      final state = container
          .read(entityTelemetryHistoryProvider(_device))
          .requireValue;
      expect(state.keys, unorderedEquals(['temperature', 'humidity']));
      contract.expectAllConform(adapter);
    });

    test('history falls back to the legacy path only on HTTP 404', () async {
      adapter.on(
        'GET',
        _latestPath,
        (_) => MockDioAdapter.jsonResponse({
          'temperature': [
            {'ts': 300, 'value': 18.0},
          ],
        }),
      );
      // No handler for _historyPath: MockDioAdapter answers 404 by default.
      container.listen(entityTelemetryHistoryProvider(_device), (_, _) {});

      final history = await container.read(
        entityTelemetryHistoryProvider(_device).future,
      );

      expect(history['temperature']!.single.numericValue, 18.0);
      expect(adapter.capturedRequests.map((r) => r.path), [
        _historyPath,
        _latestPath,
      ]);
      contract.expectAllConform(adapter);
    });

    test('a 403 on history is not retried through the legacy path', () async {
      adapter.enqueue(
        'GET',
        _historyPath,
        (_) => MockDioAdapter.jsonResponse({
          'status': 403,
          'errorCode': 20,
          'message': 'Forbidden',
        }, statusCode: 403),
      );
      container.listen(entityTelemetryHistoryProvider(_device), (_, _) {});

      await expectLater(
        container.read(entityTelemetryHistoryProvider(_device).future),
        throwsA(
          isA<TbFailure>().having(
            (f) => f.type,
            'type',
            TbFailureType.permissionDenied,
          ),
        ),
      );
      expect(adapter.capturedRequests.map((r) => r.path), [_historyPath]);
    });

    test('a slower earlier range never overwrites a newer range', () async {
      final slowGate = Completer<void>();
      adapter.on('GET', _historyPath, (opts) async {
        final endTs = opts.queryParameters['endTs'] as int;
        if (endTs == 100) {
          await slowGate.future;
          return MockDioAdapter.jsonResponse({
            'temperature': [
              {'ts': 200, 'value': 11.1},
            ],
          });
        }
        return MockDioAdapter.jsonResponse({
          'temperature': [
            {'ts': 300, 'value': 29.9},
          ],
        });
      });
      container.listen(entityTelemetryHistoryProvider(_device), (_, _) {});
      await container.read(entityTelemetryHistoryProvider(_device).future);
      final notifier = container.read(
        entityTelemetryHistoryProvider(_device).notifier,
      );

      const slowRange = TbTsHistoryQuery(
        entityId: _device,
        keys: ['temperature'],
        startTs: 1,
        endTs: 100,
      );
      const freshRange = TbTsHistoryQuery(
        entityId: _device,
        keys: ['temperature'],
        startTs: 1,
        endTs: 500,
      );
      final staleFuture = notifier.loadRange(slowRange);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      await notifier.loadRange(freshRange);
      slowGate.complete();
      await staleFuture;

      final state = container.read(entityTelemetryHistoryProvider(_device));
      expect(state.error, isNull);
      expect(state.requireValue['temperature']!.single.numericValue, 29.9);
    });

    test('a failed range load reports an error and a retry recovers', () async {
      adapter.on(
        'GET',
        _historyPath,
        (_) => MockDioAdapter.jsonResponse({
          'temperature': [
            {'ts': 100, 'value': 20.0},
          ],
        }),
      );
      container.listen(entityTelemetryHistoryProvider(_device), (_, _) {});
      await container.read(entityTelemetryHistoryProvider(_device).future);
      final notifier = container.read(
        entityTelemetryHistoryProvider(_device).notifier,
      );
      const range = TbTsHistoryQuery(
        entityId: _device,
        keys: ['temperature'],
        startTs: 1,
        endTs: 500,
      );

      adapter.enqueue(
        'GET',
        _historyPath,
        (_) => MockDioAdapter.jsonResponse({
          'status': 500,
          'message': 'Internal error',
        }, statusCode: 500),
      );
      await notifier.loadRange(range);
      final failed = container.read(entityTelemetryHistoryProvider(_device));
      expect(failed.hasError, isTrue);
      expect((failed.error! as TbFailure).type, TbFailureType.serverError);

      await notifier.loadRange(range);
      final recovered = container.read(entityTelemetryHistoryProvider(_device));
      expect(recovered.hasError, isFalse);
      expect(recovered.requireValue['temperature']!.single.numericValue, 20.0);
    });
  });

  group('Live entity telemetry stream (WebSocket)', () {
    const streamArg = (id: _device, keys: ['temperature', 'humidity']);

    test('merges the snapshot and updates, ignores older points', () async {
      final emitted = <Map<String, TbTsPoint>>[];
      container.listen(liveEntityTelemetryProvider(streamArg), (_, next) {
        final value = next.valueOrNull;
        if (value != null) emitted.add(value);
      });

      final cmdId = await awaitSentCmdId('ENTITY_DATA');
      wsChannels.first.pushServerJson({
        'cmdId': cmdId,
        'data': {
          'data': [
            {
              'entityId': {'entityType': 'DEVICE', 'id': 'dev-1'},
              'latest': {
                'TIME_SERIES': {
                  'temperature': {'ts': 1000, 'value': 21.5},
                },
              },
            },
          ],
        },
      });
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(emitted.last['temperature']!.numericValue, 21.5);

      wsChannels.first.pushServerJson({
        'cmdId': cmdId,
        'update': [
          {
            'entityId': {'entityType': 'DEVICE', 'id': 'dev-1'},
            'latest': {
              'TIME_SERIES': {
                'humidity': {'ts': 1100, 'value': 46},
              },
            },
          },
        ],
      });
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(emitted.last.keys, unorderedEquals(['temperature', 'humidity']));
      expect(emitted.last['temperature']!.numericValue, 21.5);
      expect(emitted.last['humidity']!.numericValue, 46.0);

      wsChannels.first.pushServerJson({
        'cmdId': cmdId,
        'update': [
          {
            'entityId': {'entityType': 'DEVICE', 'id': 'dev-1'},
            'latest': {
              'TIME_SERIES': {
                'temperature': {'ts': 900, 'value': 99.0},
              },
            },
          },
        ],
      });
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(
        emitted.last['temperature']!.numericValue,
        21.5,
        reason: 'an update older than the stored point must be ignored',
      );
    });

    test('closing the listener unsubscribes the ENTITY_DATA command', () async {
      final sub = container.listen(
        liveEntityTelemetryProvider(streamArg),
        (_, _) {},
      );
      final cmdId = await awaitSentCmdId('ENTITY_DATA');

      sub.close();
      await Future<void>.delayed(const Duration(milliseconds: 200));

      final unsubscribe = wsChannels.first.decodedSentFrames
          .expand((frame) => (frame['cmds'] as List<dynamic>?) ?? const [])
          .whereType<Map<String, dynamic>>()
          .where((cmd) => cmd['type'] == 'ENTITY_DATA_UNSUBSCRIBE');
      expect(unsubscribe.map((cmd) => cmd['cmdId']), [cmdId]);
    });

    test(
      'a server error frame surfaces as a TbFailure on the stream',
      () async {
        container.listen(liveEntityTelemetryProvider(streamArg), (_, _) {});
        final cmdId = await awaitSentCmdId('ENTITY_DATA');

        wsChannels.first.pushServerJson({
          'cmdId': cmdId,
          'errorCode': 2,
          'errorMsg': 'Invalid entity filter',
        });
        await Future<void>.delayed(const Duration(milliseconds: 20));

        final state = container.read(liveEntityTelemetryProvider(streamArg));
        expect(state.hasError, isTrue);
        final failure = state.error! as TbFailure;
        expect(failure.type, TbFailureType.validation);
        expect(failure.errorCode, 2);
      },
    );

    test(
      'a malformed frame becomes a stream error, not an uncaught exception',
      () async {
        container.listen(liveEntityTelemetryProvider(streamArg), (_, _) {});
        final cmdId = await awaitSentCmdId('ENTITY_DATA');

        // `update` must be a list; a bad server frame must not crash the zone.
        wsChannels.first.pushServerJson({
          'cmdId': cmdId,
          'update': 'not-a-list',
        });
        await Future<void>.delayed(const Duration(milliseconds: 20));

        final state = container.read(liveEntityTelemetryProvider(streamArg));
        expect(state.hasError, isTrue);
      },
    );
  });

  group('Telemetry controllers (demo mode)', () {
    test(
      'demo attributes support shared-scope save and delete offline',
      () async {
        await container.read(authProvider.notifier).loginDemo();
        container.listen(entityAttributesProvider(_attrsArg), (_, _) {});
        final initial = await container.read(
          entityAttributesProvider(_attrsArg).future,
        );
        expect(initial.map((a) => a.key), ['targetTemp', 'fanMode']);

        await container
            .read(entityAttributesProvider(_attrsArg).notifier)
            .saveAttributes({'targetTemp': 24.0});
        await container
            .read(entityAttributesProvider(_attrsArg).notifier)
            .deleteAttributes(['fanMode']);

        final attrs = await container.read(
          entityAttributesProvider(_attrsArg).future,
        );
        expect(attrs.map((a) => a.key), ['targetTemp']);
        expect(attrs.single.value, 24.0);
        expect(adapter.capturedRequests, isEmpty);
      },
    );

    test('demo rejects writes to client-scope attributes', () async {
      await container.read(authProvider.notifier).loginDemo();
      const clientArg = (id: _device, scope: TbAttributeScope.clientScope);
      container.listen(entityAttributesProvider(clientArg), (_, _) {});
      final client = await container.read(
        entityAttributesProvider(clientArg).future,
      );
      expect(client.single.key, 'firmwareVersion');
      expect(client.single.value, '2.4.1');

      await expectLater(
        container
            .read(entityAttributesProvider(clientArg).notifier)
            .saveAttributes({'firmwareVersion': '9.9.9'}),
        throwsA(
          isA<TbFailure>().having(
            (f) => f.type,
            'type',
            TbFailureType.validation,
          ),
        ),
      );
    });

    test(
      'demo latest values parse numeric readings from the seeded device',
      () async {
        await container.read(authProvider.notifier).loginDemo();
        container.listen(entityLatestTelemetryProvider(_device), (_, _) {});
        container.listen(
          entityLatestTelemetryProvider(
            const EntityId(entityType: EntityType.device, id: 'dev-404'),
          ),
          (_, _) {},
        );

        final latest = await container.read(
          entityLatestTelemetryProvider(_device).future,
        );
        expect(latest['temperature']!.numericValue, 21.8);
        expect(latest['humidity']!.numericValue, 46.0);
        expect(latest['rssi']!.numericValue, -58.0);
        expect(latest['temperature']!.rawValue, '21.8 °C');

        final unknown = await container.read(
          entityLatestTelemetryProvider(
            const EntityId(entityType: EntityType.device, id: 'dev-404'),
          ).future,
        );
        expect(unknown, isEmpty);
      },
    );

    test(
      'demo live stream emits one snapshot and never opens a socket',
      () async {
        await container.read(authProvider.notifier).loginDemo();
        const demoArg = (id: _device, keys: ['temperature']);
        container.listen(liveEntityTelemetryProvider(demoArg), (_, _) {});

        final snapshot = await container.read(
          liveEntityTelemetryProvider(demoArg).future,
        );

        expect(snapshot.keys, ['temperature']);
        expect(snapshot['temperature']!.numericValue, 21.8);
        expect(wsChannels, isEmpty);
      },
    );
  });
}
