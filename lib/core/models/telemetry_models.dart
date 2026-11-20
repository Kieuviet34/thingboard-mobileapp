import 'package:flutter/foundation.dart';
import 'package:thingsboard_democloud_app/core/models/entity_id.dart';

/// ThingsBoard attribute scopes.
enum TbAttributeScope {
  serverScope('SERVER_SCOPE', 'Server'),
  sharedScope('SHARED_SCOPE', 'Shared'),
  clientScope('CLIENT_SCOPE', 'Client');

  const TbAttributeScope(this.wireValue, this.label);

  final String wireValue;
  final String label;

  bool get isWritableViaRest => this != TbAttributeScope.clientScope;
}

/// Time-series aggregation modes supported by ThingsBoard REST and WS APIs.
enum TsAggregation {
  none('NONE'),
  min('MIN'),
  max('MAX'),
  avg('AVG'),
  sum('SUM'),
  count('COUNT');

  const TsAggregation(this.wireValue);

  final String wireValue;
}

/// Persistent RPC lifecycle states.
enum RpcStatus {
  queued('QUEUED'),
  sent('SENT'),
  delivered('DELIVERED'),
  successful('SUCCESSFUL'),
  timeout('TIMEOUT'),
  expired('EXPIRED'),
  failed('FAILED'),
  deleted('DELETED');

  const RpcStatus(this.wireValue);

  final String wireValue;

  static RpcStatus fromWire(String? value) {
    for (final s in RpcStatus.values) {
      if (s.wireValue == value) return s;
    }
    return RpcStatus.failed;
  }
}

/// Attribute entry returned by `/api/plugins/telemetry/.../values/attributes/{scope}`.
@immutable
class TbAttributeEntry {
  const TbAttributeEntry({
    required this.key,
    required this.value,
    required this.lastUpdateTs,
    required this.scope,
  });

  factory TbAttributeEntry.fromJson(
    Map<String, dynamic> json, {
    TbAttributeScope scope = TbAttributeScope.serverScope,
  }) {
    return TbAttributeEntry(
      key: json['key'] as String? ?? '',
      value: json['value'],
      lastUpdateTs: (json['lastUpdateTs'] as num?)?.toInt() ?? 0,
      scope: scope,
    );
  }

  final String key;
  final Object? value;
  final int lastUpdateTs;
  final TbAttributeScope scope;

  String get displayValue => value?.toString() ?? '—';
}

/// Single time-series data point with safe numeric parsing for both strict and stringified values.
@immutable
class TbTsPoint {
  const TbTsPoint({
    required this.ts,
    required this.rawValue,
    this.numericValue,
  });

  factory TbTsPoint.fromJson(Map<String, dynamic> json) {
    final raw = json['value'];
    final double? parsed = switch (raw) {
      num n => n.toDouble(),
      String s => double.tryParse(s),
      bool b => b ? 1.0 : 0.0,
      _ => null,
    };
    return TbTsPoint(
      ts: (json['ts'] as num?)?.toInt() ?? 0,
      rawValue: raw,
      numericValue: parsed,
    );
  }

  final int ts;
  final Object? rawValue;
  final double? numericValue;

  String get displayValue => rawValue?.toString() ?? '—';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TbTsPoint &&
          runtimeType == other.runtimeType &&
          ts == other.ts &&
          rawValue == other.rawValue;

  @override
  int get hashCode => Object.hash(ts, rawValue);
}

/// Historical time-series query parameters.
@immutable
class TbTsHistoryQuery {
  const TbTsHistoryQuery({
    required this.entityId,
    required this.keys,
    required this.startTs,
    required this.endTs,
    this.intervalMs = 0,
    this.limit = 100,
    this.agg = TsAggregation.none,
  });

  final EntityId entityId;
  final List<String> keys;
  final int startTs;
  final int endTs;
  final int intervalMs;
  final int limit;
  final TsAggregation agg;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TbTsHistoryQuery &&
          runtimeType == other.runtimeType &&
          entityId == other.entityId &&
          listEquals(keys, other.keys) &&
          startTs == other.startTs &&
          endTs == other.endTs &&
          intervalMs == other.intervalMs &&
          limit == other.limit &&
          agg == other.agg;

  @override
  int get hashCode => Object.hash(
    entityId,
    Object.hashAll(keys),
    startTs,
    endTs,
    intervalMs,
    limit,
    agg,
  );
}

/// One-way or two-way RPC command request body.
@immutable
class TbRpcRequest {
  const TbRpcRequest({
    required this.method,
    this.params = const {},
    this.timeoutMs = 10000,
    this.persistent = false,
    this.retries = 0,
  });

  final String method;
  final Map<String, dynamic> params;
  final int timeoutMs;
  final bool persistent;
  final int retries;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'method': method,
    'params': params,
    'timeout': timeoutMs < 5000 ? 5000 : timeoutMs,
    'persistent': persistent,
    if (persistent) 'retries': retries,
  };
}

/// Persistent RPC record from `/api/rpc/persistent/*`.
@immutable
class TbPersistentRpc {
  const TbPersistentRpc({
    required this.id,
    required this.deviceId,
    required this.createdTime,
    required this.status,
    this.expirationTime = 0,
    this.request = const {},
    this.response,
  });

  factory TbPersistentRpc.fromJson(Map<String, dynamic> json) {
    final idObj = EntityId.maybeFromJson(json['id']);
    final devObj = EntityId.maybeFromJson(json['deviceId']);
    return TbPersistentRpc(
      id: idObj?.id ?? (json['id'] as String? ?? ''),
      deviceId: devObj?.id ?? '',
      createdTime: (json['createdTime'] as num?)?.toInt() ?? 0,
      expirationTime: (json['expirationTime'] as num?)?.toInt() ?? 0,
      status: RpcStatus.fromWire(json['status'] as String?),
      request: json['request'] as Map<String, dynamic>? ?? const {},
      response: json['response'],
    );
  }

  final String id;
  final String deviceId;
  final int createdTime;
  final int expirationTime;
  final RpcStatus status;
  final Map<String, dynamic> request;
  final Object? response;
}
