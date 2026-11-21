import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'mock_dio_adapter.dart';

/// The mock must behave like the real adapters, or tests that rely on it
/// (stale-response guards, session resets) prove nothing.
void main() {
  late MockDioAdapter adapter;
  late Dio dio;

  setUp(() {
    adapter = MockDioAdapter();
    dio = Dio(BaseOptions(baseUrl: 'https://tb.example.com'))
      ..httpClientAdapter = adapter;
  });

  test('records requests and decoded JSON responses', () async {
    adapter.on(
      'GET',
      '/api/ping',
      (_) => MockDioAdapter.jsonResponse({'ok': true}),
    );

    final response = await dio.get<Map<String, dynamic>>('/api/ping');

    expect(response.data, {'ok': true});
    expect(adapter.capturedRequests.single.path, '/api/ping');
    final captured = adapter.capturedResponses.single;
    expect(captured.statusCode, 200);
    expect(captured.json, {'ok': true});
  });

  test(
    'a cancelled in-flight request fails with cancel, not a stale reply',
    () async {
      final gate = Completer<void>();
      adapter.on('GET', '/api/slow', (_) async {
        await gate.future;
        return MockDioAdapter.jsonResponse({'late': true});
      });
      final token = CancelToken();

      final call = dio.get<Map<String, dynamic>>(
        '/api/slow',
        cancelToken: token,
      );
      await Future<void>.delayed(Duration.zero);
      token.cancel('session reset');
      gate.complete();

      await expectLater(
        call,
        throwsA(
          isA<DioException>().having(
            (e) => e.type,
            'type',
            DioExceptionType.cancel,
          ),
        ),
      );
      // The late payload never reaches the caller.
      expect(adapter.capturedResponses.where((r) => r.json != null), isEmpty);
    },
  );

  test(
    'empty and unregistered responses carry no JSON for validation',
    () async {
      adapter.on('GET', '/api/empty', (_) => MockDioAdapter.emptyResponse());

      await dio.get<dynamic>('/api/empty');
      expect(adapter.capturedResponses.single.json, isNull);

      await expectLater(
        dio.get<dynamic>('/api/unknown'),
        throwsA(isA<DioException>()),
      );
      expect(adapter.capturedResponses.last.statusCode, 404);
    },
  );
}
