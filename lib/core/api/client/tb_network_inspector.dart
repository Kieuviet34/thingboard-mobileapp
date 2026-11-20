import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Recorded HTTP/REST or WebSocket network transaction for data audit.
@immutable
class TbNetworkLogEntry {
  const TbNetworkLogEntry({
    required this.id,
    required this.timestamp,
    required this.method,
    required this.url,
    this.statusCode,
    this.durationMs,
    this.requestHeaders = const {},
    this.requestBody,
    this.responseBody,
    this.errorMessage,
    this.isError = false,
  });

  final String id;
  final DateTime timestamp;
  final String method;
  final String url;
  final int? statusCode;
  final int? durationMs;
  final Map<String, dynamic> requestHeaders;
  final dynamic requestBody;
  final dynamic responseBody;
  final String? errorMessage;
  final bool isError;

  String get prettyRequestBody {
    if (requestBody == null) return 'Empty';
    try {
      if (requestBody is Map || requestBody is List) {
        return const JsonEncoder.withIndent('  ').convert(requestBody);
      }
      return requestBody.toString();
    } catch (_) {
      return requestBody.toString();
    }
  }

  String get prettyResponseBody {
    if (responseBody == null) return 'Empty';
    try {
      if (responseBody is Map || responseBody is List) {
        return const JsonEncoder.withIndent('  ').convert(responseBody);
      }
      return responseBody.toString();
    } catch (_) {
      return responseBody.toString();
    }
  }
}

/// In-memory ring buffer of the most recent network entries (last 50).
class TbNetworkLogNotifier extends Notifier<List<TbNetworkLogEntry>> {
  @override
  List<TbNetworkLogEntry> build() => const [];

  void record(TbNetworkLogEntry entry) {
    state = [entry, ...state.take(49)];
  }

  void clear() {
    state = const [];
  }
}

final tbNetworkLogProvider =
    NotifierProvider<TbNetworkLogNotifier, List<TbNetworkLogEntry>>(
      TbNetworkLogNotifier.new,
    );

/// Global logger facade usable from repositories (Live and Demo mode) and interceptors.
abstract final class TbNetworkLog {
  static void Function(TbNetworkLogEntry entry)? _onLog;

  static void registerSink(void Function(TbNetworkLogEntry entry)? sink) {
    _onLog = sink;
  }

  static void record({
    required String method,
    required String url,
    int? statusCode,
    int? durationMs,
    Map<String, dynamic>? requestHeaders,
    dynamic requestBody,
    dynamic responseBody,
    String? errorMessage,
    bool isError = false,
  }) {
    try {
      final entry = TbNetworkLogEntry(
        id: '${method}_${DateTime.now().microsecondsSinceEpoch}',
        timestamp: DateTime.now(),
        method: method,
        url: url,
        statusCode: statusCode,
        durationMs: durationMs,
        requestHeaders: requestHeaders ?? const {},
        requestBody: requestBody,
        responseBody: responseBody,
        errorMessage: errorMessage,
        isError: isError,
      );
      _onLog?.call(entry);
    } catch (_) {
      // Non-fatal: sink disconnected or widget tree unmounted
    }
  }
}

/// Dio Interceptor logging all outgoing HTTP requests and incoming responses.
class TbNetworkLogInterceptor extends Interceptor {
  TbNetworkLogInterceptor();

  final _startTimes = <RequestOptions, int>{};

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    _startTimes[options] = DateTime.now().millisecondsSinceEpoch;
    super.onRequest(options, handler);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    final start = _startTimes.remove(response.requestOptions);
    final duration = start != null
        ? DateTime.now().millisecondsSinceEpoch - start
        : null;

    final sanitizedHeaders = <String, dynamic>{
      for (final e in response.requestOptions.headers.entries)
        if (e.key.toLowerCase().contains('auth'))
          e.key: 'Bearer ***'
        else
          e.key: e.value,
    };

    TbNetworkLog.record(
      method: response.requestOptions.method,
      url: response.requestOptions.uri.toString(),
      statusCode: response.statusCode,
      durationMs: duration,
      requestHeaders: sanitizedHeaders,
      requestBody: response.requestOptions.data,
      responseBody: response.data,
      isError: (response.statusCode ?? 200) >= 400,
    );

    super.onResponse(response, handler);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    final start = _startTimes.remove(err.requestOptions);
    final duration = start != null
        ? DateTime.now().millisecondsSinceEpoch - start
        : null;

    TbNetworkLog.record(
      method: err.requestOptions.method,
      url: err.requestOptions.uri.toString(),
      statusCode: err.response?.statusCode,
      durationMs: duration,
      requestBody: err.requestOptions.data,
      responseBody: err.response?.data,
      errorMessage: err.message,
      isError: true,
    );

    super.onError(err, handler);
  }
}
