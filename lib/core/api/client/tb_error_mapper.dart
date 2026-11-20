import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:thingsboard_democloud_app/core/models/tb_failure.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// Normalizes [DioException], ThingsBoard JSON payloads, and WebSocket errors
/// directly into [TbFailure] using raw integer `errorCode` values.
abstract final class TbErrorMapper {
  static TbFailure fromException(Object error) {
    if (error is TbFailure) return error;

    if (error is DioException) {
      return _fromDioException(error);
    }

    if (error is WebSocketChannelException) {
      return TbFailure(
        type: TbFailureType.networkUnavailable,
        message: error.message ?? 'WebSocket connection failed',
      );
    }

    return TbFailure(type: TbFailureType.unknown, message: error.toString());
  }

  /// Maps a WebSocket response `errorCode` (0..4) into a [TbFailure].
  static TbFailure fromWsErrorCode(int errorCode, String? errorMsg) {
    final type = switch (errorCode) {
      2 => TbFailureType.validation,
      3 => TbFailureType.tokenExpired,
      4 => TbFailureType.permissionDenied,
      _ => TbFailureType.serverError,
    };
    return TbFailure(
      type: type,
      errorCode: errorCode,
      message: errorMsg ?? 'WebSocket error ($errorCode)',
    );
  }

  static TbFailure _fromDioException(DioException e) {
    switch (e.type) {
      case DioExceptionType.cancel:
        return const TbFailure(
          type: TbFailureType.cancelled,
          message: 'Request cancelled',
        );
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.transformTimeout:
      case DioExceptionType.connectionError:
        return const TbFailure(
          type: TbFailureType.networkUnavailable,
          message: 'Network unavailable or request timed out',
        );
      case DioExceptionType.badCertificate:
        return const TbFailure(
          type: TbFailureType.networkUnavailable,
          message: 'Untrusted server SSL certificate',
        );
      case DioExceptionType.badResponse:
      case DioExceptionType.unknown:
        final inner = e.error;
        if (inner is TbFailure) return inner;
        final response = e.response;
        if (response != null) {
          return _fromHttpResponse(
            statusCode: response.statusCode,
            data: response.data,
            fallbackMessage: e.message,
          );
        }
        return TbFailure(
          type: TbFailureType.networkUnavailable,
          message: e.message ?? 'Network request failed',
        );
    }
  }

  static TbFailure _fromHttpResponse({
    int? statusCode,
    Object? data,
    String? fallbackMessage,
  }) {
    final jsonMap = _tryParseMap(data);
    final rawErrorCode = (jsonMap?['errorCode'] as num?)?.toInt();
    final subErrorCode = (jsonMap?['subscriptionErrorCode'] as num?)?.toInt();
    final message = (jsonMap?['message'] as String?)?.trim().isNotEmpty == true
        ? jsonMap!['message'] as String
        : ((jsonMap?['error'] as String?) ??
              fallbackMessage ??
              'Request failed (${statusCode ?? 'unknown'})');

    if (rawErrorCode != null) {
      return TbFailure(
        type: _mapPlatformErrorCode(rawErrorCode, statusCode),
        message: message,
        statusCode: statusCode,
        errorCode: rawErrorCode,
        subscriptionErrorCode: subErrorCode,
      );
    }

    final type = switch (statusCode) {
      400 => TbFailureType.validation,
      401 => TbFailureType.invalidCredentials,
      403 => TbFailureType.permissionDenied,
      404 => TbFailureType.notFound,
      406 => TbFailureType.invalidDeviceRpcReply,
      409 => TbFailureType.conflict,
      429 => TbFailureType.rateLimited,
      504 => TbFailureType.deviceOfflineOrTimeout,
      final code when code != null && code >= 500 => TbFailureType.serverError,
      _ => TbFailureType.unknown,
    };

    return TbFailure(type: type, message: message, statusCode: statusCode);
  }

  static TbFailureType _mapPlatformErrorCode(int code, int? statusCode) {
    return switch (code) {
      2 => TbFailureType.serverError,
      10 => TbFailureType.invalidCredentials,
      11 || 12 => TbFailureType.tokenExpired,
      15 => TbFailureType.passwordExpired,
      20 => TbFailureType.permissionDenied,
      30 || 31 => TbFailureType.validation,
      32 => TbFailureType.notFound,
      33 || 34 => TbFailureType.rateLimited,
      35 => TbFailureType.conflict,
      40 || 41 => TbFailureType.quotaExceeded,
      45 => TbFailureType.passwordPolicy,
      46 || 47 || 50 => TbFailureType.serverError,
      _ =>
        statusCode == 403
            ? TbFailureType.permissionDenied
            : TbFailureType.unknown,
    };
  }

  static Map<String, dynamic>? _tryParseMap(Object? data) {
    if (data is Map<String, dynamic>) return data;
    if (data is String && data.trim().startsWith('{')) {
      try {
        final decoded = jsonDecode(data);
        if (decoded is Map<String, dynamic>) return decoded;
      } catch (_) {
        return null;
      }
    }
    return null;
  }
}
