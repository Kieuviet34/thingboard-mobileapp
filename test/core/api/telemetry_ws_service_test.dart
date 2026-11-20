import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thingsboard_democloud_app/core/api/ws/telemetry_ws_service.dart';
import 'package:thingsboard_democloud_app/core/models/tb_failure.dart';

import '../../helpers/fake_ws_channel.dart';

void main() {
  group('TbWebSocketService', () {
    test(
      'sends authCmd on connect and multiplexes subscriptions by cmdId',
      () async {
        late FakeWebSocketChannel channel;
        final service = TbWebSocketService(
          wsUriProvider: () =>
              Uri.parse('wss://thingsboard.democloud.xyz/api/ws'),
          tokenProvider: () async => 'jwt-token-1',
          channelFactory: (_) {
            channel = FakeWebSocketChannel();
            return channel;
          },
        );
        addTearDown(service.dispose);

        await service.connect();

        expect(channel.decodedSentFrames.first, <String, dynamic>{
          'authCmd': {'cmdId': 0, 'token': 'jwt-token-1'},
        });

        final receivedA = <Map<String, dynamic>>[];
        final receivedB = <Map<String, dynamic>>[];

        final subA = service
            .subscribe(
              type: WsCommandType.entityData,
              payload: <String, dynamic>{'query': {}},
            )
            .listen(receivedA.add);
        final subB = service
            .subscribe(
              type: WsCommandType.alarmCount,
              payload: <String, dynamic>{'query': {}},
            )
            .listen(receivedB.add);

        await Future<void>.delayed(Duration.zero);

        final frames = channel.decodedSentFrames;
        final cmdA = (frames[1]['cmds'] as List).first as Map<String, dynamic>;
        final cmdB = (frames[2]['cmds'] as List).first as Map<String, dynamic>;
        expect(cmdA['cmdId'], isNot(cmdB['cmdId']));
        expect(cmdA['type'], 'ENTITY_DATA');
        expect(cmdB['type'], 'ALARM_COUNT');

        channel.pushServerJson(<String, dynamic>{
          'cmdId': cmdA['cmdId'],
          'errorCode': 0,
          'cmdUpdateType': 'ENTITY_DATA',
          'data': {'data': []},
        });
        channel.pushServerJson(<String, dynamic>{
          'cmdId': cmdB['cmdId'],
          'errorCode': 0,
          'cmdUpdateType': 'ALARM_COUNT_DATA',
          'count': 7,
        });

        await Future<void>.delayed(Duration.zero);

        expect(receivedA, hasLength(1));
        expect(receivedB.single['count'], 7);

        await subA.cancel();
        await subB.cancel();
      },
    );

    test('emits 30s application heartbeat (<90s server idle timeout)', () {
      fakeAsync((async) {
        late FakeWebSocketChannel channel;
        final service = TbWebSocketService(
          wsUriProvider: () => Uri.parse('wss://example.com/api/ws'),
          tokenProvider: () async => 'jwt-1',
          channelFactory: (_) {
            channel = FakeWebSocketChannel();
            return channel;
          },
          heartbeatInterval: const Duration(seconds: 30),
        );

        unawaited(service.connect());
        async.flushMicrotasks();

        // Only authCmd sent initially.
        expect(channel.decodedSentFrames, hasLength(1));

        async.elapse(const Duration(seconds: 31));
        expect(channel.decodedSentFrames.length, greaterThanOrEqualTo(2));

        async.elapse(const Duration(seconds: 30));
        expect(channel.decodedSentFrames.length, greaterThanOrEqualTo(3));

        unawaited(service.dispose());
        async.flushMicrotasks();
      });
    });

    test(
      'reconnects with fresh JWT, replays active subs, and drops disposed-while-offline subs',
      () async {
        final channels = <FakeWebSocketChannel>[];
        var tokenCounter = 0;

        final service = TbWebSocketService(
          wsUriProvider: () => Uri.parse('wss://example.com/api/ws'),
          tokenProvider: () async => 'jwt-${++tokenCounter}',
          channelFactory: (_) {
            final ch = FakeWebSocketChannel();
            channels.add(ch);
            return ch;
          },
          baseReconnectDelay: const Duration(milliseconds: 10),
        );
        addTearDown(service.dispose);

        await service.connect();

        final keptEvents = <Map<String, dynamic>>[];
        final subKeep = service
            .subscribe(
              type: WsCommandType.alarmData,
              payload: <String, dynamic>{
                'query': {'k': 1},
              },
            )
            .listen(keptEvents.add);
        final subDrop = service
            .subscribe(
              type: WsCommandType.entityCount,
              payload: <String, dynamic>{
                'query': {'k': 2},
              },
            )
            .listen((_) {});

        await Future<void>.delayed(Duration.zero);
        final gen1 = service.socketGeneration;

        // Drop socket, then cancel subDrop while offline.
        await channels.first.simulateServerClose(1006, 'dropped');
        await subDrop.cancel();

        await Future<void>.delayed(const Duration(milliseconds: 60));

        expect(channels.length, greaterThanOrEqualTo(2));
        expect(service.socketGeneration, greaterThan(gen1));

        final secondFrames = channels[1].decodedSentFrames;
        expect(secondFrames.first['authCmd']['token'], 'jwt-2');

        // Replayed commands must include ONLY ALARM_DATA (subDrop was cancelled offline).
        final replayedTypes = secondFrames
            .skip(1)
            .expand((f) => (f['cmds'] as List? ?? const []))
            .map((c) => (c as Map<String, dynamic>)['type'])
            .toList();
        expect(replayedTypes, contains('ALARM_DATA'));
        expect(replayedTypes, isNot(contains('ENTITY_COUNT')));

        // Stale frame from old socket channel[0] is ignored cleanly.
        channels[0].pushServerJson({'cmdId': 1, 'errorCode': 0, 'stale': true});
        await Future<void>.delayed(Duration.zero);
        expect(keptEvents, isEmpty);

        await subKeep.cancel();
      },
    );

    test(
      'per-command unsubscribe: NOTIFICATIONS_COUNT does NOT emit server unsubscribe frame',
      () async {
        late FakeWebSocketChannel channel;
        final service = TbWebSocketService(
          wsUriProvider: () => Uri.parse('wss://example.com/api/ws'),
          tokenProvider: () async => 'jwt-1',
          channelFactory: (_) {
            channel = FakeWebSocketChannel();
            return channel;
          },
        );
        addTearDown(service.dispose);

        await service.connect();

        final subNotifCount = service
            .subscribe(type: WsCommandType.notificationsCount)
            .listen((_) {});
        final subEntity = service
            .subscribe(
              type: WsCommandType.entityData,
              payload: <String, dynamic>{'query': {}},
            )
            .listen((_) {});
        final subV1 = service
            .subscribe(
              type: WsCommandType.attributes,
              payload: <String, dynamic>{
                'entityType': 'DEVICE',
                'entityId': 'dev-1',
                'scope': 'SERVER_SCOPE',
              },
            )
            .listen((_) {});

        await Future<void>.delayed(Duration.zero);
        final beforeCancelCount = channel.decodedSentFrames.length;

        await subNotifCount.cancel();
        await Future<void>.delayed(Duration.zero);
        // No frame sent for NOTIFICATIONS_COUNT.
        expect(channel.decodedSentFrames.length, beforeCancelCount);

        await subEntity.cancel();
        await subV1.cancel();
        await Future<void>.delayed(Duration.zero);

        final sentAfter = channel.decodedSentFrames
            .skip(beforeCancelCount)
            .toList();
        final unsubTypes = sentAfter
            .expand((f) => (f['cmds'] as List))
            .cast<Map<String, dynamic>>()
            .toList();
        expect(
          unsubTypes.any((c) => c['type'] == 'ENTITY_DATA_UNSUBSCRIBE'),
          isTrue,
        );
        expect(
          unsubTypes.any(
            (c) => c['type'] == 'ATTRIBUTES' && c['unsubscribe'] == true,
          ),
          isTrue,
        );
      },
    );

    test('maps WS errorCode 3 and 4 to TbFailure on matching stream', () async {
      late FakeWebSocketChannel channel;
      final service = TbWebSocketService(
        wsUriProvider: () => Uri.parse('wss://example.com/api/ws'),
        tokenProvider: () async => 'jwt-1',
        channelFactory: (_) {
          channel = FakeWebSocketChannel();
          return channel;
        },
      );
      addTearDown(service.dispose);

      await service.connect();

      final errors = <Object>[];
      final sub = service
          .subscribe(
            type: WsCommandType.alarmStatus,
            payload: <String, dynamic>{},
          )
          .listen((_) {}, onError: errors.add);

      await Future<void>.delayed(Duration.zero);
      final cmdId =
          ((channel.decodedSentFrames[1]['cmds'] as List).first
              as Map)['cmdId'];

      channel.pushServerJson({
        'cmdId': cmdId,
        'errorCode': 4,
        'errorMsg': 'Forbidden',
      });
      await Future<void>.delayed(Duration.zero);

      expect(errors.single, isA<TbFailure>());
      expect((errors.single as TbFailure).type, TbFailureType.permissionDenied);

      await sub.cancel();
    });

    test(
      'merges partial ENTITY_DATA update frames by ts and preserves untouched keys',
      () {
        final initial = mergeEntityDataUpdates(
          current: const {},
          frame: const <String, dynamic>{
            'data': {
              'data': [
                {
                  'entityId': {'entityType': 'DEVICE', 'id': 'dev-1'},
                  'latest': {
                    'TIME_SERIES': {
                      'temperature': {'ts': 1000, 'value': '22.0'},
                      'humidity': {'ts': 1000, 'value': '45'},
                    },
                  },
                },
              ],
            },
          },
        );

        final merged = mergeEntityDataUpdates(
          current: initial,
          frame: const <String, dynamic>{
            'update': [
              {
                'entityId': {'entityType': 'DEVICE', 'id': 'dev-1'},
                'latest': {
                  'TIME_SERIES': {
                    'temperature': {'ts': 2000, 'value': '23.5'},
                    // Out-of-order older ts for humidity must be ignored
                    'humidity': {'ts': 900, 'value': '99'},
                  },
                },
              },
            ],
          },
        );

        expect(merged['dev-1']?['temperature']?.numericValue, 23.5);
        expect(merged['dev-1']?['humidity']?.numericValue, 45);
      },
    );

    test(
      'pauses on AppLifecycleState.paused and reconnects on resumed',
      () async {
        final channels = <FakeWebSocketChannel>[];
        final service = TbWebSocketService(
          wsUriProvider: () => Uri.parse('wss://example.com/api/ws'),
          tokenProvider: () async => 'jwt-1',
          channelFactory: (_) {
            final ch = FakeWebSocketChannel();
            channels.add(ch);
            return ch;
          },
        );
        addTearDown(service.dispose);

        await service.connect();
        final sub = service
            .subscribe(type: WsCommandType.entityCount)
            .listen((_) {});
        await Future<void>.delayed(Duration.zero);

        await service.handleAppLifecycleState(AppLifecycleState.paused);
        expect(service.currentState, WsConnectionState.disconnected);

        await service.handleAppLifecycleState(AppLifecycleState.resumed);
        expect(channels.length, 2);
        expect(service.currentState, WsConnectionState.authenticated);

        await sub.cancel();
      },
    );
  });
}
