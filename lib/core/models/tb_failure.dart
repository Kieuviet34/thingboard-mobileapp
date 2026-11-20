import 'package:flutter/foundation.dart';

/// Canonical failure categories across ThingsBoard PE REST, WebSocket, and network layers.
enum TbFailureType {
  invalidCredentials,
  tokenExpired,
  trialExpired,
  passwordExpired,
  permissionDenied,
  validation,
  notFound,
  rateLimited,
  conflict,
  quotaExceeded,
  passwordPolicy,
  serverError,
  invalidDeviceRpcReply,
  deviceOfflineOrTimeout,
  networkUnavailable,
  cancelled,
  unknown,
}

/// Typed, immutable domain failure surfaced by repositories, controllers, and WS streams.
@immutable
class TbFailure implements Exception {
  const TbFailure({
    required this.type,
    required this.message,
    this.statusCode,
    this.errorCode,
    this.subscriptionErrorCode,
  });

  final TbFailureType type;
  final String message;
  final int? statusCode;
  final int? errorCode;
  final int? subscriptionErrorCode;

  /// True when the request was intentionally cancelled (e.g. `sessionGeneration` bump).
  bool get isCancelled => type == TbFailureType.cancelled;

  /// True when the failure represents an authentication or session expiration rejection.
  bool get isAuthFailure =>
      type == TbFailureType.invalidCredentials ||
      type == TbFailureType.tokenExpired ||
      type == TbFailureType.passwordExpired;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TbFailure &&
          runtimeType == other.runtimeType &&
          type == other.type &&
          message == other.message &&
          statusCode == other.statusCode &&
          errorCode == other.errorCode &&
          subscriptionErrorCode == other.subscriptionErrorCode;

  @override
  int get hashCode =>
      Object.hash(type, message, statusCode, errorCode, subscriptionErrorCode);

  @override
  String toString() =>
      'TbFailure(type: $type, statusCode: $statusCode, errorCode: $errorCode, message: $message)';
}
