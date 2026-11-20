import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

typedef MockRouteHandler =
    FutureOr<ResponseBody> Function(RequestOptions options);

/// Boundary-only Dio [HttpClientAdapter] for deterministic HTTP testing.
class MockDioAdapter implements HttpClientAdapter {
  final Map<String, MockRouteHandler> _handlers = {};
  final Map<String, Queue<MockRouteHandler>> _queuedHandlers = {};
  final List<RequestOptions> capturedRequests = [];

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
    return ResponseBody.fromString(
      encoded,
      statusCode,
      headers:
          headers ??
          <String, List<String>>{
            Headers.contentTypeHeader: <String>[Headers.jsonContentType],
          },
    );
  }

  /// Builds an empty [ResponseBody] (e.g. HTTP 504 or 200 empty).
  static ResponseBody emptyResponse({int statusCode = 200}) {
    return ResponseBody.fromString('', statusCode);
  }

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    capturedRequests.add(options);
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
  void close({bool force = false}) {}
}
