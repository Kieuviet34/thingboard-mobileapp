import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

typedef MockRouteHandler =
    FutureOr<ResponseBody> Function(RequestOptions options);

/// A response the mock produced, kept with its request and decoded JSON so
/// contract tests can validate the payload shape.
final class CapturedResponse {
  const CapturedResponse(this.request, this.statusCode, this.json);

  final RequestOptions request;
  final int statusCode;

  /// The object passed to [MockDioAdapter.jsonResponse], or `null` when the
  /// response was empty/non-JSON.
  final Object? json;
}

/// Boundary-only Dio [HttpClientAdapter] for deterministic HTTP testing.
///
/// Like the real adapters it honors request cancellation: when Dio's cancel
/// future completes before the handler answers, the call fails with a
/// `DioExceptionType.cancel` instead of delivering a stale response.
class MockDioAdapter implements HttpClientAdapter {
  final Map<String, MockRouteHandler> _handlers = {};
  final Map<String, Queue<MockRouteHandler>> _queuedHandlers = {};
  final List<RequestOptions> capturedRequests = [];
  final List<CapturedResponse> capturedResponses = [];

  static final Expando<Object> _jsonBodies = Expando<Object>('mock json body');

  static String _key(String method, String path) =>
      '${method.toUpperCase()} $path';

  /// Registers a persistent handler for `(method, path)`.
  void on(String method, String path, MockRouteHandler handler) {
    _handlers[_key(method, path)] = handler;
  }

  /// Enqueues a one-shot handler for `(method, path)` consumed in FIFO order.
  void enqueue(String method, String path, MockRouteHandler handler) {
    final k = _key(method, path);
    _queuedHandlers.putIfAbsent(k, Queue<MockRouteHandler>.new).add(handler);
  }

  /// Builds a JSON [ResponseBody] with UTF-8 encoding.
  static ResponseBody jsonResponse(
    Object? body, {
    int statusCode = 200,
    Map<String, List<String>>? headers,
  }) {
    final encoded = body == null ? '' : jsonEncode(body);
    final response = ResponseBody.fromString(
      encoded,
      statusCode,
      headers:
          headers ??
          <String, List<String>>{
            Headers.contentTypeHeader: <String>[Headers.jsonContentType],
          },
    );
    if (body != null) _jsonBodies[response] = body;
    return response;
  }

  /// Builds an empty [ResponseBody] (e.g. HTTP 504 or 200 empty).
  static ResponseBody emptyResponse({int statusCode = 200}) {
    return ResponseBody.fromString('', statusCode);
  }

  Future<ResponseBody> _route(RequestOptions options) async {
    final k = _key(options.method, options.path);
    final queue = _queuedHandlers[k];
    if (queue != null && queue.isNotEmpty) {
      final handler = queue.removeFirst();
      return await handler(options);
    }
    final handler = _handlers[k];
    if (handler != null) {
      return await handler(options);
    }
    return jsonResponse(<String, dynamic>{
      'status': 404,
      'error': 'Not Found',
      'message': 'No mock registered for $k',
      'path': options.path,
    }, statusCode: 404);
  }

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    capturedRequests.add(options);
    final answer = _route(options);
    final response = cancelFuture == null
        ? await answer
        : await Future.any<ResponseBody>([
            answer,
            cancelFuture.then<ResponseBody>(
              (_) => throw DioException.requestCancelled(
                requestOptions: options,
                reason: 'cancelled by caller',
              ),
            ),
          ]);
    capturedResponses.add(
      CapturedResponse(options, response.statusCode, _jsonBodies[response]),
    );
    return response;
  }

  @override
  void close({bool force = false}) {}
}
