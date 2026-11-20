import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:thingsboard_democloud_app/core/api/client/tb_secure_storage.dart';
import 'package:thingsboard_democloud_app/core/api/controllers/asset_controller.dart';
import 'package:thingsboard_democloud_app/core/api/controllers/audit_log_controller.dart';
import 'package:thingsboard_democloud_app/core/api/controllers/auth_controller.dart';
import 'package:thingsboard_democloud_app/core/api/controllers/customer_controller.dart';
import 'package:thingsboard_democloud_app/core/api/controllers/notification_controller.dart';
import 'package:thingsboard_democloud_app/core/api/controllers/rpc_controller.dart';
import 'package:thingsboard_democloud_app/core/api/controllers/server_config_controller.dart';
import 'package:thingsboard_democloud_app/core/api/controllers/telemetry_controller.dart';
import 'package:thingsboard_democloud_app/core/api/controllers/user_profile_controller.dart';
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
    prefs = FakeAppPreferences();
    wsChannels = [];
    container = createTestContainer(
      overrides: [
        tbStorageProvider.overrideWithValue(storage),
        tbAppPreferencesProvider.overrideWithValue(prefs),
        tbHttpClientAdapterProvider.overrideWithValue(adapter),
        wsChannelFactoryProvider.overrideWithValue((_) {
          final ch = FakeWebSocketChannel();
          wsChannels.add(ch);
          return ch;
        }),
      ],
    );
  });

  group(
    'Telemetry, RPC, Asset, Customer, Notifications, AuditLog, UserProfile controllers',
    () {
      test(
        'TelemetryHistoryNotifier discards stale range response when newer range completes',
        () async {
          const entity = EntityId(entityType: EntityType.device, id: 'dev-1');
          final slowGate = Completer<void>();

          // Initial build call
          adapter.enqueue(
            'GET',
            '/api/plugins/telemetry/DEVICE/dev-1/values/timeseries/history',
            (_) => MockDioAdapter.jsonResponse({
              'temperature': [
                {'ts': 100, 'value': 20.0},
              ],
            }),
          );
          container.listen(entityTelemetryHistoryProvider(entity), (_, _) {});
          await container.read(entityTelemetryHistoryProvider(entity).future);

          // Slow older range call
          adapter.enqueue(
            'GET',
            '/api/plugins/telemetry/DEVICE/dev-1/values/timeseries/history',
            (_) async {
              await slowGate.future;
              return MockDioAdapter.jsonResponse({
                'temperature': [
                  {'ts': 200, 'value': 11.1},
                ],
              });
            },
          );
          // Fast newer range call
          adapter.enqueue(
            'GET',
            '/api/plugins/telemetry/DEVICE/dev-1/values/timeseries/history',
            (_) => MockDioAdapter.jsonResponse({
              'temperature': [
                {'ts': 300, 'value': 29.9},
              ],
            }),
          );

          final notifier = container.read(
            entityTelemetryHistoryProvider(entity).notifier,
          );
          final staleFuture = notifier.loadRange(
            const TbTsHistoryQuery(
              entityId: entity,
              keys: ['temperature'],
              startTs: 1,
              endTs: 100,
            ),
          );
          await Future<void>.delayed(const Duration(milliseconds: 10));
          await notifier.loadRange(
            const TbTsHistoryQuery(
              entityId: entity,
              keys: ['temperature'],
              startTs: 1,
              endTs: 500,
            ),
          );
          slowGate.complete();
          await staleFuture;

          final state = container
              .read(entityTelemetryHistoryProvider(entity))
              .requireValue;
          expect(state['temperature']?.single.numericValue, 29.9);
        },
      );

      test('RpcNotifier ignores late response when disposed', () async {
        final gate = Completer<void>();
        adapter.on('POST', '/api/rpc/twoway/dev-1', (_) async {
          await gate.future;
          return MockDioAdapter.jsonResponse({'ok': true});
        });

        final sub = container.listen(rpcControllerProvider('dev-1'), (_, _) {});
        final execFuture = container
            .read(rpcControllerProvider('dev-1').notifier)
            .execute(request: const TbRpcRequest(method: 'ping'), twoWay: true);
        await Future<void>.delayed(const Duration(milliseconds: 10));
        sub.close(); // triggers autoDispose while RPC is in flight
        gate.complete();
        await execFuture;
      });

      test(
        'UserProfileController.changePassword persists returned JwtPair in storage',
        () async {
          adapter.on(
            'GET',
            '/api/auth/user',
            (_) => MockDioAdapter.jsonResponse({
              'id': {'entityType': 'USER', 'id': 'u-1'},
              'email': 'tenant@tb.io',
              'authority': 'TENANT_ADMIN',
            }),
          );
          adapter.on(
            'POST',
            '/api/auth/changePassword',
            (_) => MockDioAdapter.jsonResponse({
              'token': 'rotated-jwt',
              'refreshToken': 'rotated-refresh',
            }),
          );

          await container.read(userProfileControllerProvider.future);
          await container
              .read(userProfileControllerProvider.notifier)
              .changePassword(
                currentPassword: 'old',
                newPassword: 'newPassword1!',
              );

          expect(await storage.read(TbStorageKeys.accessToken), 'rotated-jwt');
          expect(
            await storage.read(TbStorageKeys.refreshToken),
            'rotated-refresh',
          );
        },
      );

      test(
        'unreadNotificationsCountProvider uses WS NOTIFICATIONS_COUNT without emitting unsubscribe',
        () async {
          adapter.on('GET', '/api/notifications/unread/count', (_) {
            return MockDioAdapter.jsonResponse(3);
          });

          final counts = <int>[];
          final sub = container.listen(unreadNotificationsCountProvider, (
            _,
            next,
          ) {
            if (next.hasValue) counts.add(next.requireValue);
          });

          await Future<void>.delayed(const Duration(milliseconds: 30));
          expect(counts, contains(3));
          expect(wsChannels, isNotEmpty);

          final cmdId =
              ((wsChannels.first.decodedSentFrames[1]['cmds'] as List).first
                  as Map)['cmdId'];
          wsChannels.first.pushServerJson({
            'cmdId': cmdId,
            'errorCode': 0,
            'totalUnreadCount': 9,
          });

          await Future<void>.delayed(const Duration(milliseconds: 20));
          expect(counts, contains(9));

          final sentBeforeDispose = wsChannels.first.decodedSentFrames.length;
          sub.close();
          await Future<void>.delayed(const Duration(milliseconds: 20));
          expect(wsChannels.first.decodedSentFrames.length, sentBeforeDispose);
        },
      );

      test(
        'Demo Asset relations, Customer list, AuditLogs, and Notifications mutations work offline',
        () async {
          await container.read(authProvider.notifier).loginDemo();

          final assets = await container.read(
            assetsListProvider(const TbAssetQuery()).future,
          );
          expect(assets.items, isNotEmpty);
          final relations = await container.read(
            entityRelationsProvider((
              entity: EntityId(
                entityType: EntityType.asset,
                id: assets.items.first.id,
              ),
              outgoing: true,
            )).future,
          );
          expect(relations, isNotEmpty);

          final customers = await container.read(
            customersListProvider(null).future,
          );
          expect(customers.items, isNotEmpty);

          final logs = await container.read(
            auditLogsListProvider(const TbAuditLogQuery()).future,
          );
          expect(logs.items, isNotEmpty);

          final notifs = await container.read(
            notificationsListProvider(false).future,
          );
          final unreadId = notifs.items.firstWhere((n) => !n.isRead).id;
          await container
              .read(notificationsListProvider(false).notifier)
              .markAsRead(unreadId);
          final updated = container
              .read(notificationsListProvider(false))
              .requireValue;
          expect(
            updated.items.firstWhere((n) => n.id == unreadId).isRead,
            isTrue,
          );
        },
      );
    },
  );
}
