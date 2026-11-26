import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:thingsboard_democloud_app/core/api/client/tb_secure_storage.dart';
import 'package:thingsboard_democloud_app/core/api/controllers/auth_controller.dart';
import 'package:thingsboard_democloud_app/core/api/controllers/server_config_controller.dart';
import 'package:thingsboard_democloud_app/core/api/controllers/user_profile_controller.dart';
import 'package:thingsboard_democloud_app/core/api/ws/telemetry_ws_service.dart';
import 'package:thingsboard_democloud_app/core/models/models.dart';

import '../../../helpers/fake_app_preferences.dart';
import '../../../helpers/fake_secure_storage.dart';
import '../../../helpers/fake_ws_channel.dart';
import '../../../helpers/mock_dio_adapter.dart';
import '../../../helpers/test_container.dart';

String _jwt(String marker) {
  final exp =
      DateTime.now().add(const Duration(hours: 2)).millisecondsSinceEpoch ~/
      1000;
  final h = base64Url.encode(utf8.encode('{"alg":"HS512"}'));
  final p = base64Url.encode(
    utf8.encode('{"sub":"$marker@tb.io","userId":"u-1","exp":$exp}'),
  );
  return '$h.$p.sig';
}

class _GatedStorage extends FakeSecureStorage {
  Completer<void>? refreshGate;

  @override
  Future<String?> read(String key) async {
    if (key == TbStorageKeys.refreshToken && refreshGate != null) {
      await refreshGate!.future;
    }
    return super.read(key);
  }
}

void main() {
  Future<
    ({ProviderContainer c, _GatedStorage s, List<FakeWebSocketChannel> ch})
  >
  setup() async {
    final adapter = MockDioAdapter();
    final storage = _GatedStorage();
    final channels = <FakeWebSocketChannel>[];
    adapter
      ..on(
        'GET',
        '/api/noauth/userPasswordPolicy',
        (_) => MockDioAdapter.jsonResponse({'minimumLength': 6}),
      )
      ..on(
        'POST',
        '/api/noauth/oauth2Clients',
        (_) => MockDioAdapter.jsonResponse([]),
      )
      ..on(
        'GET',
        '/api/system/info',
        (_) => MockDioAdapter.jsonResponse({'version': '4.4.1PE'}),
      )
      ..on(
        'GET',
        '/api/auth/user',
        (_) => MockDioAdapter.jsonResponse({
          'id': {'entityType': 'USER', 'id': 'u-1'},
          'email': 'tenant@tb.io',
          'authority': 'TENANT_ADMIN',
        }),
      );
    final container = createTestContainer(
      overrides: [
        tbStorageProvider.overrideWithValue(storage),
        tbAppPreferencesProvider.overrideWithValue(FakeAppPreferences()),
        tbHttpClientAdapterProvider.overrideWithValue(adapter),
        wsChannelFactoryProvider.overrideWithValue((_) {
          final ch = FakeWebSocketChannel();
          channels.add(ch);
          return ch;
        }),
      ],
    );
    addTearDown(container.dispose);
    await container.read(authProvider.future);
    await container
        .read(authProvider.notifier)
        .completeOAuth2(accessToken: _jwt('old'), refreshToken: 'old-refresh');
    await Future<void>.delayed(Duration.zero);
    return (c: container, s: storage, ch: channels);
  }

  test(
    'syncSessionTokens discards result when logout happens mid-read',
    () async {
      final env = await setup();
      final ws = env.c.read(telemetryWsServiceProvider);
      final sub = ws
          .subscribe(
            type: WsCommandType.alarmCount,
            payload: <String, dynamic>{'query': {}},
          )
          .listen((_) {});
      await Future<void>.delayed(Duration.zero);
      final before = env.ch.length;

      await env.s.write(TbStorageKeys.accessToken, _jwt('new'));
      env.s.refreshGate = Completer<void>();
      final pending = env.c.read(authProvider.notifier).syncSessionTokens();
      await Future<void>.delayed(Duration.zero);

      await env.c.read(authProvider.notifier).logout();
      env.s.refreshGate!.complete();
      await pending;
      await Future<void>.delayed(Duration.zero);

      expect(env.c.read(authProvider).valueOrNull, isA<AuthUnauthenticated>());
      expect(
        env.ch.length,
        before,
        reason: 'WS must not reconnect after logout',
      );
      await sub.cancel();
    },
  );

  test(
    'changePassword re-authenticates the shared WS and refreshes auth session',
    () async {
      final adapter = MockDioAdapter();
      final storage = FakeSecureStorage();
      final channels = <FakeWebSocketChannel>[];
      final oldJwt = _jwt('old');
      final newJwt = _jwt('new');

      adapter
        ..on(
          'GET',
          '/api/noauth/userPasswordPolicy',
          (_) => MockDioAdapter.jsonResponse({'minimumLength': 6}),
        )
        ..on(
          'POST',
          '/api/noauth/oauth2Clients',
          (_) => MockDioAdapter.jsonResponse([]),
        )
        ..on(
          'GET',
          '/api/system/info',
          (_) => MockDioAdapter.jsonResponse({'version': '4.4.1PE'}),
        )
        ..on(
          'GET',
          '/api/auth/user',
          (_) => MockDioAdapter.jsonResponse({
            'id': {'entityType': 'USER', 'id': 'u-1'},
            'email': 'tenant@tb.io',
            'authority': 'TENANT_ADMIN',
          }),
        )
        ..on(
          'POST',
          '/api/auth/changePassword',
          (_) => MockDioAdapter.jsonResponse({
            'token': newJwt,
            'refreshToken': 'rotated-refresh',
          }),
        );

      final container = createTestContainer(
        overrides: [
          tbStorageProvider.overrideWithValue(storage),
          tbAppPreferencesProvider.overrideWithValue(FakeAppPreferences()),
          tbHttpClientAdapterProvider.overrideWithValue(adapter),
          wsChannelFactoryProvider.overrideWithValue((_) {
            final ch = FakeWebSocketChannel();
            channels.add(ch);
            return ch;
          }),
        ],
      );
      addTearDown(container.dispose);

      await container.read(authProvider.future);
      await container
          .read(authProvider.notifier)
          .completeOAuth2(accessToken: oldJwt, refreshToken: 'old-refresh');
      await Future<void>.delayed(Duration.zero);

      final ws = container.read(telemetryWsServiceProvider);
      final received = <Map<String, dynamic>>[];
      final sub = ws
          .subscribe(
            type: WsCommandType.alarmCount,
            payload: <String, dynamic>{'query': {}},
          )
          .listen(received.add);
      await Future<void>.delayed(Duration.zero);

      expect(channels, hasLength(1));
      expect(
        channels.first.decodedSentFrames.first['authCmd']['token'],
        oldJwt,
      );

      await container.read(userProfileControllerProvider.future);
      await container
          .read(userProfileControllerProvider.notifier)
          .changePassword(currentPassword: 'old', newPassword: 'newPassword1!');
      await Future<void>.delayed(Duration.zero);

      // Single shared service reconnects with the new token and replays subs.
      expect(channels, hasLength(2));
      expect(channels.last.decodedSentFrames.first['authCmd']['token'], newJwt);
      expect(
        channels.last.decodedSentFrames.any((f) => f.containsKey('cmds')),
        isTrue,
      );
      expect((channels.first.sink as FakeWebSocketSink).isClosed, isTrue);
      expect(ws.currentState, WsConnectionState.authenticated);

      // Auth state carries the rotated tokens and is still authenticated.
      final auth = container.read(authProvider).valueOrNull;
      expect(auth, isA<AuthAuthenticated>());
      final session = (auth as AuthAuthenticated).session;
      expect(session.accessToken, newJwt);
      expect(session.refreshToken, 'rotated-refresh');
      expect(await storage.read(TbStorageKeys.accessToken), newJwt);

      await sub.cancel();
    },
  );
}
