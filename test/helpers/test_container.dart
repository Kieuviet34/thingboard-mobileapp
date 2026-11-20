import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:thingsboard_democloud_app/constants/app_constants.dart';

import 'mock_dio_adapter.dart';

/// Creates a [Dio] instance wired to [MockDioAdapter] for boundary testing.
Dio createTestDio(
  MockDioAdapter adapter, {
  String baseUrl = ThingsboardAppConstants.defaultApiEndpoint,
}) {
  final dio = Dio(
    BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: 5),
      receiveTimeout: const Duration(seconds: 5),
      headers: const {'Content-Type': 'application/json'},
    ),
  );
  dio.httpClientAdapter = adapter;
  return dio;
}

/// Creates a [ProviderContainer] with automatic disposal via `addTearDown`.
ProviderContainer createTestContainer({List<Override> overrides = const []}) {
  final container = ProviderContainer(overrides: overrides);
  addTearDown(container.dispose);
  return container;
}
