import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:thingsboard_democloud_app/core/api/client/tb_auth_interceptor.dart';
import 'package:thingsboard_democloud_app/core/api/client/tb_error_mapper.dart';
import 'package:thingsboard_democloud_app/core/api/client/tb_network_inspector.dart';
import 'package:thingsboard_democloud_app/core/api/client/tb_secure_storage.dart';
import 'package:thingsboard_democloud_app/core/models/tb_failure.dart';

/// Typed HTTP client facade managing host-scoped `CancelToken`s,
/// `sessionGeneration` checks, and [TbErrorMapper] normalization.
class TbApiClient {
  TbApiClient({
    required String baseUrl,
    required TbStorage storage,
    HttpClientAdapter? httpClientAdapter,
    VoidCallback? onSessionInvalidated,
  }) {
    _dio = Dio(
      BaseOptions(
        baseUrl: _normalizeBaseUrl(baseUrl),
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 15),
        headers: const <String, dynamic>{'Content-Type': 'application/json'},
      ),
    );
    if (httpClientAdapter != null) {
      _dio.httpClientAdapter = httpClientAdapter;
    }
    _coordinator = TbAuthSessionCoordinator(
      storage: storage,
      dio: _dio,
      onSessionInvalidated: onSessionInvalidated,
    );
    _dio.interceptors.add(TbAuthInterceptor(coordinator: _coordinator));
    _dio.interceptors.add(TbNetworkLogInterceptor());
  }

  late final Dio _dio;
  late final TbAuthSessionCoordinator _coordinator;
  CancelToken _sessionCancelToken = CancelToken();

  Dio get dio => _dio;
  TbAuthSessionCoordinator get coordinator => _coordinator;
  int get sessionGeneration => _coordinator.sessionGeneration;
  String get baseUrl => _dio.options.baseUrl;

  /// Updates the base URL, bumps `sessionGeneration`, and cancels all active requests.
  void switchBaseUrl(String newBaseUrl) {
    resetSessionScope();
    _dio.options.baseUrl = _normalizeBaseUrl(newBaseUrl);
    _coordinator.syncClientConfig();
  }

  /// Cancels all in-flight requests and increments `sessionGeneration`.
  int resetSessionScope([String reason = 'Session scope changed']) {
    final gen = _coordinator.bumpSessionGeneration();
    if (!_sessionCancelToken.isCancelled) {
      _sessionCancelToken.cancel(reason);
    }
    _sessionCancelToken = CancelToken();
    return gen;
  }

  Future<Response<T>> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
  }) => _execute<T>(
    () => _dio.get<T>(
      path,
      queryParameters: queryParameters,
      options: options,
      cancelToken: cancelToken ?? _sessionCancelToken,
    ),
  );

  Future<Response<T>> post<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
  }) => _execute<T>(
    () => _dio.post<T>(
      path,
      data: data,
      queryParameters: queryParameters,
      options: options,
      cancelToken: cancelToken ?? _sessionCancelToken,
    ),
  );

  Future<Response<T>> put<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
  }) => _execute<T>(
    () => _dio.put<T>(
      path,
      data: data,
      queryParameters: queryParameters,
      options: options,
      cancelToken: cancelToken ?? _sessionCancelToken,
    ),
  );

  Future<Response<T>> delete<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
  }) => _execute<T>(
    () => _dio.delete<T>(
      path,
      data: data,
      queryParameters: queryParameters,
      options: options,
      cancelToken: cancelToken ?? _sessionCancelToken,
    ),
  );

  Future<Response<T>> _execute<T>(Future<Response<T>> Function() call) async {
    final gen = _coordinator.sessionGeneration;
    try {
      final response = await call();
      if (gen != _coordinator.sessionGeneration) {
        throw const TbFailure(
          type: TbFailureType.cancelled,
          message: 'Session changed while request was in flight',
        );
      }
      return response;
    } catch (error) {
      if (gen != _coordinator.sessionGeneration) {
        throw const TbFailure(
          type: TbFailureType.cancelled,
          message: 'Session changed while request was in flight',
        );
      }
      throw TbErrorMapper.fromException(error);
    }
  }

  static String _normalizeBaseUrl(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return '/';
    return trimmed.endsWith('/') ? trimmed : '$trimmed/';
  }
}
