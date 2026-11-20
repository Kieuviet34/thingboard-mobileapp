import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thingsboard_democloud_app/core/api/client/tb_api_client.dart';
import 'package:thingsboard_democloud_app/core/api/client/tb_auth_interceptor.dart';
import 'package:thingsboard_democloud_app/core/api/client/tb_error_mapper.dart';
import 'package:thingsboard_democloud_app/core/api/client/tb_secure_storage.dart';
import 'package:thingsboard_democloud_app/core/models/tb_failure.dart';

import '../../helpers/fake_secure_storage.dart';
import '../../helpers/mock_dio_adapter.dart';
import '../../helpers/test_container.dart';

String _buildFakeJwt({required Duration expiresIn}) {
  final expSeconds =
      DateTime.now().add(expiresIn).millisecondsSinceEpoch ~/ 1000;
  final header = base64Url.encode(utf8.encode('{"alg":"HS512","typ":"JWT"}'));
  final payload = base64Url.encode(
    utf8.encode('{"sub":"tenant@tb.io","exp":$expSeconds}'),
  );
  return '$header.$payload.sig';
}

void main() {
  late MockDioAdapter adapter;
  late FakeSecureStorage storage;
  late Dio dio;
  late TbAuthSessionCoordinator coordinator;
  late int invalidatedCalls;

  setUp(() {
    adapter = MockDioAdapter();
    storage = FakeSecureStorage();
    dio = createTestDio(adapter);
    invalidatedCalls = 0;
    coordinator = TbAuthSessionCoordinator(
      storage: storage,
      dio: dio,
      onSessionInvalidated: () => invalidatedCalls++,
    );
    dio.interceptors.add(TbAuthInterceptor(coordinator: coordinator));
  });

  group('TbAuthInterceptor & TbAuthSessionCoordinator', () {
    test(
      'attaches X-Authorization Bearer header and skips auth/noauth routes',
      () async {
        final token = _buildFakeJwt(expiresIn: const Duration(hours: 2));
        await storage.write(TbStorageKeys.accessToken, token);

        adapter.on(
          'GET',
          '/api/auth/user',
          (_) => MockDioAdapter.jsonResponse({'email': 'tenant@tb.io'}),
        );
        adapter.on(
          'POST',
          '/api/auth/login',
          (_) =>
              MockDioAdapter.jsonResponse({'token': 't', 'refreshToken': 'r'}),
        );
        adapter.on(
          'GET',
          '/api/noauth/userPasswordPolicy',
          (_) => MockDioAdapter.jsonResponse({'minimumLength': 6}),
        );

        await dio.get<dynamic>('/api/auth/user');
        await dio.post<dynamic>('/api/auth/login', data: {'username': 'a'});
        await dio.get<dynamic>('/api/noauth/userPasswordPolicy');

        expect(
          adapter.capturedRequests[0].headers['X-Authorization'],
          'Bearer $token',
        );
        expect(adapter.capturedRequests[0].headers['Authorization'], isNull);
        expect(adapter.capturedRequests[1].headers['X-Authorization'], isNull);
        expect(adapter.capturedRequests[2].headers['X-Authorization'], isNull);
      },
    );

    test(
      'coalesces 3 concurrent 401 (errorCode 11) into 1 refresh and replays all 3',
      () async {
        final initialToken = _buildFakeJwt(expiresIn: const Duration(hours: 1));
        final freshToken = _buildFakeJwt(expiresIn: const Duration(hours: 2));
        await storage.write(TbStorageKeys.accessToken, initialToken);
        await storage.write(TbStorageKeys.refreshToken, 'refresh-1');

        var refreshCount = 0;
        var initial401s = 0;
        final all401sSent = Completer<void>();
        final refreshStarted = Completer<void>();
        final refreshGate = Completer<void>();

        adapter.on('POST', '/api/auth/token', (options) async {
          refreshCount++;
          if (!refreshStarted.isCompleted) {
            refreshStarted.complete();
          }
          await refreshGate.future;
          return MockDioAdapter.jsonResponse({
            'token': freshToken,
            'refreshToken': 'refresh-2',
          });
        });

        for (final path in ['/api/devices', '/api/alarms', '/api/dashboards']) {
          adapter.enqueue('GET', path, (_) {
            initial401s++;
            if (initial401s == 3 && !all401sSent.isCompleted) {
              all401sSent.complete();
            }
            return MockDioAdapter.jsonResponse({
              'status': 401,
              'errorCode': 11,
              'message': 'Token has expired',
            }, statusCode: 401);
          });
          adapter.enqueue(
            'GET',
            path,
            (opts) => MockDioAdapter.jsonResponse({'ok': opts.path}),
          );
        }

        final futures = [
          dio.get<Map<String, dynamic>>('/api/devices'),
          dio.get<Map<String, dynamic>>('/api/alarms'),
          dio.get<Map<String, dynamic>>('/api/dashboards'),
        ];

        await Future.wait([all401sSent.future, refreshStarted.future]);
        await Future<void>.delayed(Duration.zero);
        expect(refreshCount, 1);
        refreshGate.complete();

        final responses = await Future.wait(futures);
        expect(responses.map((r) => r.data?['ok']), [
          '/api/devices',
          '/api/alarms',
          '/api/dashboards',
        ]);
        expect(refreshCount, 1);
        expect(await storage.read(TbStorageKeys.accessToken), freshToken);
        expect(await storage.read(TbStorageKeys.refreshToken), 'refresh-2');
      },
    );

    test(
      'proactive expiry check and reactive 401 share the same single-flight lock',
      () async {
        final expiringSoon = _buildFakeJwt(
          expiresIn: const Duration(seconds: 10),
        );
        final freshToken = _buildFakeJwt(expiresIn: const Duration(hours: 2));
        await storage.write(TbStorageKeys.accessToken, expiringSoon);
        await storage.write(TbStorageKeys.refreshToken, 'refresh-1');

        var refreshCount = 0;
        final refreshStarted = Completer<void>();
        final refreshGate = Completer<void>();
        adapter.on('POST', '/api/auth/token', (_) async {
          refreshCount++;
          if (!refreshStarted.isCompleted) {
            refreshStarted.complete();
          }
          await refreshGate.future;
          return MockDioAdapter.jsonResponse({
            'token': freshToken,
            'refreshToken': 'refresh-2',
          });
        });
        adapter.on(
          'GET',
          '/api/devices',
          (_) => MockDioAdapter.jsonResponse({'ok': true}),
        );

        final proactiveFuture = dio.get<dynamic>('/api/devices');
        final reactiveFuture = coordinator.refreshAccessToken();

        await refreshStarted.future;
        await Future<void>.delayed(Duration.zero);
        expect(refreshCount, 1);
        refreshGate.complete();

        await Future.wait([proactiveFuture, reactiveFuture]);
        expect(refreshCount, 1);
      },
    );

    test(
      'refresh failure (401/malformed) clears storage and invalidates session',
      () async {
        final token = _buildFakeJwt(expiresIn: const Duration(hours: 1));
        await storage.write(TbStorageKeys.accessToken, token);
        await storage.write(TbStorageKeys.refreshToken, 'bad-refresh');

        adapter.enqueue(
          'GET',
          '/api/devices',
          (_) => MockDioAdapter.jsonResponse({
            'status': 401,
            'errorCode': 11,
            'message': 'Expired',
          }, statusCode: 401),
        );
        adapter.on(
          'POST',
          '/api/auth/token',
          (_) => MockDioAdapter.jsonResponse({
            'status': 401,
            'errorCode': 10,
            'message': 'Refresh token expired',
          }, statusCode: 401),
        );

        await expectLater(
          dio.get<dynamic>('/api/devices'),
          throwsA(isA<DioException>()),
        );

        expect(await storage.read(TbStorageKeys.accessToken), isNull);
        expect(await storage.read(TbStorageKeys.refreshToken), isNull);
        expect(invalidatedCalls, 1);
      },
    );

    test(
      'errorCode 10 (bad credentials) does not trigger token refresh',
      () async {
        final token = _buildFakeJwt(expiresIn: const Duration(hours: 1));
        await storage.write(TbStorageKeys.accessToken, token);
        await storage.write(TbStorageKeys.refreshToken, 'r1');

        var refreshCalled = false;
        adapter.on('POST', '/api/auth/token', (_) {
          refreshCalled = true;
          return MockDioAdapter.jsonResponse({});
        });
        adapter.on(
          'GET',
          '/api/devices',
          (_) => MockDioAdapter.jsonResponse({
            'status': 401,
            'errorCode': 10,
            'message': 'Authentication failed',
          }, statusCode: 401),
        );

        try {
          await dio.get<dynamic>('/api/devices');
          fail('Expected DioException');
        } on DioException catch (e) {
          final failure = TbErrorMapper.fromException(e);
          expect(failure.type, TbFailureType.invalidCredentials);
        }

        expect(refreshCalled, isFalse);
      },
    );

    test(
      'sessionGeneration bump during in-flight refresh discards late tokens and cancels replay',
      () async {
        final oldToken = _buildFakeJwt(expiresIn: const Duration(hours: 1));
        final lateFreshToken = _buildFakeJwt(
          expiresIn: const Duration(hours: 2),
        );
        await storage.write(TbStorageKeys.accessToken, oldToken);
        await storage.write(TbStorageKeys.refreshToken, 'refresh-1');

        final refreshStarted = Completer<void>();
        final refreshGate = Completer<void>();
        var replayed = false;

        adapter.enqueue(
          'GET',
          '/api/devices',
          (_) => MockDioAdapter.jsonResponse({
            'status': 401,
            'errorCode': 11,
            'message': 'Expired',
          }, statusCode: 401),
        );
        adapter.enqueue('GET', '/api/devices', (_) {
          replayed = true;
          return MockDioAdapter.jsonResponse({'ok': true});
        });
        adapter.on('POST', '/api/auth/token', (_) async {
          if (!refreshStarted.isCompleted) {
            refreshStarted.complete();
          }
          await refreshGate.future;
          return MockDioAdapter.jsonResponse({
            'token': lateFreshToken,
            'refreshToken': 'refresh-2',
          });
        });

        final future = dio.get<dynamic>('/api/devices');
        await refreshStarted.future;

        // Simulate logout / host switch mid-refresh.
        coordinator.bumpSessionGeneration();
        await storage.deleteAll();
        refreshGate.complete();

        try {
          await future;
          fail('Expected cancellation error');
        } on DioException catch (e) {
          final failure = TbErrorMapper.fromException(e);
          expect(failure.type, TbFailureType.cancelled);
        }

        expect(replayed, isFalse);
        expect(await storage.read(TbStorageKeys.accessToken), isNull);
        expect(await storage.read(TbStorageKeys.refreshToken), isNull);
      },
    );

    test(
      'TbApiClient.switchBaseUrl cancels in-flight requests and updates refresh baseUrl',
      () async {
        final client = TbApiClient(
          baseUrl: 'https://host-a.example.com',
          storage: storage,
          httpClientAdapter: adapter,
        );
        final token = _buildFakeJwt(expiresIn: const Duration(hours: 1));
        await storage.write(TbStorageKeys.accessToken, token);

        final requestStarted = Completer<void>();
        final gate = Completer<void>();
        adapter.on('GET', '/api/devices', (_) async {
          if (!requestStarted.isCompleted) {
            requestStarted.complete();
          }
          await gate.future;
          return MockDioAdapter.jsonResponse({'host': 'a'});
        });

        final inFlight = client.get<dynamic>('/api/devices');
        await requestStarted.future;

        client.switchBaseUrl('https://host-b.example.com');
        gate.complete();

        await expectLater(
          inFlight,
          throwsA(
            isA<TbFailure>().having(
              (f) => f.type,
              'type',
              TbFailureType.cancelled,
            ),
          ),
        );
        expect(client.baseUrl, 'https://host-b.example.com/');
        expect(client.sessionGeneration, 1);
      },
    );
  });
}
