import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:jwt_decoder/jwt_decoder.dart';
import 'package:thingsboard_democloud_app/core/api/client/tb_error_mapper.dart';
import 'package:thingsboard_democloud_app/core/api/client/tb_secure_storage.dart';
import 'package:thingsboard_democloud_app/core/models/auth_models.dart';
import 'package:thingsboard_democloud_app/core/models/tb_failure.dart';

/// Coordinates single-flight JWT refreshes and monotonic session generations
/// shared across proactive expiry checks and reactive HTTP 401 retries.
class TbAuthSessionCoordinator {
  TbAuthSessionCoordinator({
    required TbStorage storage,
    required Dio dio,
    this.onSessionInvalidated,
    this.proactiveSkew = const Duration(seconds: 60),
  }) : _storage = storage,
       _dio = dio,
       _refreshDio = Dio(dio.options)
         ..httpClientAdapter = dio.httpClientAdapter;

  final TbStorage _storage;
  final Dio _dio;
  final Dio _refreshDio;
  final VoidCallback? onSessionInvalidated;
  final Duration proactiveSkew;

  int _sessionGeneration = 0;
  Completer<String?>? _refreshCompleter;
  int? _refreshGeneration;

  int get sessionGeneration => _sessionGeneration;
  Dio get dio => _dio;

  /// Syncs baseUrl and adapter onto the bare refresh [Dio] client.
  void syncClientConfig() {
    _refreshDio.options = _dio.options;
    _refreshDio.httpClientAdapter = _dio.httpClientAdapter;
  }

  /// Increments generation to invalidate any in-flight responses or refreshes
  /// belonging to a prior session, host, or [SessionMode].
  int bumpSessionGeneration() {
    _sessionGeneration++;
    return _sessionGeneration;
  }

  /// Returns a valid access token, triggering a single-flight refresh if it
  /// is expired or within [proactiveSkew] of expiration.
  Future<String?> getAccessTokenForRequest() async {
    final gen = _sessionGeneration;
    final token = await _storage.read(TbStorageKeys.accessToken);
    if (gen != _sessionGeneration) return null;
    if (token == null || token.isEmpty) return null;

    if (_isExpiringSoon(token)) {
      return refreshAccessToken(
        expectedGeneration: gen,
        failedAccessToken: token,
      );
    }
    return token;
  }

  /// Performs a single-flight `POST /api/auth/token` exchange.
  ///
  /// Uses a dedicated bare [_refreshDio] (no [TbAuthInterceptor]) so refresh
  /// calls never deadlock with request/error interceptors.
  Future<String?> refreshAccessToken({
    int? expectedGeneration,
    String? failedAccessToken,
  }) {
    final gen = expectedGeneration ?? _sessionGeneration;
    if (gen != _sessionGeneration) {
      return Future<String?>.error(
        DioException(
          requestOptions: RequestOptions(path: '/api/auth/token'),
          type: DioExceptionType.cancel,
        ),
      );
    }

    final existing = _refreshCompleter;
    if (existing != null && _refreshGeneration == gen) {
      return existing.future;
    }

    final completer = Completer<String?>();
    _refreshCompleter = completer;
    _refreshGeneration = gen;

    unawaited(_runRefresh(completer, gen, failedAccessToken));
    return completer.future;
  }

  Future<void> _runRefresh(
    Completer<String?> completer,
    int gen,
    String? failedAccessToken,
  ) async {
    try {
      // If another request already rotated the stored token, reuse it.
      if (failedAccessToken != null) {
        final currentToken = await _storage.read(TbStorageKeys.accessToken);
        if (gen != _sessionGeneration) {
          throw DioException(
            requestOptions: RequestOptions(path: '/api/auth/token'),
            type: DioExceptionType.cancel,
          );
        }
        if (currentToken != null &&
            currentToken.isNotEmpty &&
            currentToken != failedAccessToken &&
            !_isExpiringSoon(currentToken)) {
          completer.complete(currentToken);
          return;
        }
      }

      final refreshToken = await _storage.read(TbStorageKeys.refreshToken);
      if (gen != _sessionGeneration) {
        throw DioException(
          requestOptions: RequestOptions(path: '/api/auth/token'),
          type: DioExceptionType.cancel,
        );
      }
      if (refreshToken == null || refreshToken.isEmpty) {
        throw const TbFailure(
          type: TbFailureType.tokenExpired,
          message: 'Session expired. Please sign in again.',
        );
      }

      syncClientConfig();
      final response = await _refreshDio.post<dynamic>(
        '/api/auth/token',
        data: <String, dynamic>{'refreshToken': refreshToken},
      );

      if (gen != _sessionGeneration) {
        throw DioException(
          requestOptions: response.requestOptions,
          type: DioExceptionType.cancel,
        );
      }

      final data = response.data;
      if (data is! Map<String, dynamic>) {
        throw const TbFailure(
          type: TbFailureType.tokenExpired,
          message: 'Malformed token refresh response.',
        );
      }

      final parsed = LoginResponse.fromJson(data);
      if (parsed.token.isEmpty) {
        throw const TbFailure(
          type: TbFailureType.tokenExpired,
          message: 'Empty token in refresh response.',
        );
      }

      await _storage.write(TbStorageKeys.accessToken, parsed.token);
      if (parsed.refreshToken != null && parsed.refreshToken!.isNotEmpty) {
        await _storage.write(TbStorageKeys.refreshToken, parsed.refreshToken!);
      }

      if (gen != _sessionGeneration) {
        throw DioException(
          requestOptions: response.requestOptions,
          type: DioExceptionType.cancel,
        );
      }

      completer.complete(parsed.token);
    } catch (error, stackTrace) {
      final isCancelled =
          gen != _sessionGeneration ||
          (error is DioException && error.type == DioExceptionType.cancel) ||
          (error is TbFailure && error.isCancelled);

      if (!isCancelled && gen == _sessionGeneration) {
        bumpSessionGeneration();
        await _storage.delete(TbStorageKeys.accessToken);
        await _storage.delete(TbStorageKeys.refreshToken);
        onSessionInvalidated?.call();
      }

      completer.completeError(error, stackTrace);
    } finally {
      if (identical(_refreshCompleter, completer)) {
        _refreshCompleter = null;
        _refreshGeneration = null;
      }
    }
  }

  bool _isExpiringSoon(String token) {
    final decoded = JwtDecoder.tryDecode(token);
    if (decoded == null) return false;
    final exp = (decoded['exp'] as num?)?.toInt();
    if (exp == null) return false;
    final expiresAt = DateTime.fromMillisecondsSinceEpoch(exp * 1000);
    return !expiresAt.isAfter(DateTime.now().add(proactiveSkew));
  }
}

/// Attaches `X-Authorization: Bearer <jwt>` and handles single-flight 401 refresh.
class TbAuthInterceptor extends Interceptor {
  TbAuthInterceptor({required this.coordinator});

  final TbAuthSessionCoordinator coordinator;

  static const _extraSkipAuth = 'tb_skip_auth';
  static const _extraSessionGen = 'tb_session_gen';
  static const _extraUsedToken = 'tb_used_token';
  static const _extraRetried = 'tb_retried';

  bool _isAuthExcluded(RequestOptions options) {
    if (options.extra[_extraSkipAuth] == true) return true;
    final path = options.path;
    return path.startsWith('/api/auth/login') ||
        path.startsWith('/api/auth/token') ||
        path.startsWith('/api/noauth/');
  }

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    final gen = coordinator.sessionGeneration;
    options.extra[_extraSessionGen] = gen;

    if (_isAuthExcluded(options)) {
      handler.next(options);
      return;
    }

    try {
      final token = await coordinator.getAccessTokenForRequest();
      if (gen != coordinator.sessionGeneration) {
        handler.reject(
          DioException(requestOptions: options, type: DioExceptionType.cancel),
        );
        return;
      }
      if (token != null && token.isNotEmpty) {
        options.headers['X-Authorization'] = 'Bearer $token';
        options.extra[_extraUsedToken] = token;
      }
      handler.next(options);
    } on DioException catch (e) {
      handler.reject(e);
    } catch (e) {
      handler.reject(DioException(requestOptions: options, error: e));
    }
  }

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    final options = err.requestOptions;
    if (_isAuthExcluded(options) || options.extra[_extraRetried] == true) {
      handler.next(err);
      return;
    }

    final failure = TbErrorMapper.fromException(err);
    final shouldRefresh =
        err.response?.statusCode == 401 &&
        failure.type == TbFailureType.tokenExpired;

    if (!shouldRefresh) {
      handler.next(err);
      return;
    }

    final gen =
        (options.extra[_extraSessionGen] as int?) ??
        coordinator.sessionGeneration;
    if (gen != coordinator.sessionGeneration) {
      handler.reject(
        DioException(requestOptions: options, type: DioExceptionType.cancel),
      );
      return;
    }

    final usedToken = options.extra[_extraUsedToken] as String?;

    try {
      final freshToken = await coordinator.refreshAccessToken(
        expectedGeneration: gen,
        failedAccessToken: usedToken,
      );
      if (gen != coordinator.sessionGeneration ||
          freshToken == null ||
          freshToken.isEmpty) {
        handler.reject(
          DioException(requestOptions: options, type: DioExceptionType.cancel),
        );
        return;
      }

      options.headers['X-Authorization'] = 'Bearer $freshToken';
      options.extra[_extraUsedToken] = freshToken;
      options.extra[_extraRetried] = true;
      final replayed = await coordinator.dio.fetch<dynamic>(options);
      if (gen != coordinator.sessionGeneration) {
        handler.reject(
          DioException(requestOptions: options, type: DioExceptionType.cancel),
        );
        return;
      }
      handler.resolve(replayed);
    } on DioException catch (e) {
      handler.reject(e);
    } catch (e) {
      handler.reject(DioException(requestOptions: options, error: e));
    }
  }
}
