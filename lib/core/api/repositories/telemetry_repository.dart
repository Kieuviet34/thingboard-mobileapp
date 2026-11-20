import 'package:dio/dio.dart';
import 'package:thingsboard_democloud_app/core/api/client/tb_api_client.dart';
import 'package:thingsboard_democloud_app/core/mock/mock_data.dart';
import 'package:thingsboard_democloud_app/core/models/entity_id.dart';
import 'package:thingsboard_democloud_app/core/models/tb_failure.dart';
import 'package:thingsboard_democloud_app/core/models/telemetry_models.dart';

/// REST telemetry & attributes boundary (with strict data types & 404-only history fallback).
abstract interface class TelemetryRepository {
  Future<List<TbAttributeEntry>> getAttributes(
    EntityId entityId,
    TbAttributeScope scope,
  );

  Future<void> saveAttributes(
    EntityId entityId,
    TbAttributeScope scope,
    Map<String, dynamic> attributes,
  );

  Future<void> deleteAttributes(
    EntityId entityId,
    TbAttributeScope scope,
    List<String> keys,
  );

  Future<Map<String, TbTsPoint>> getLatestTimeseries(
    EntityId entityId, {
    List<String>? keys,
  });

  Future<Map<String, List<TbTsPoint>>> getTimeseriesHistory(
    TbTsHistoryQuery query, {
    CancelToken? cancelToken,
  });
}

final class RestTelemetryRepository implements TelemetryRepository {
  RestTelemetryRepository({required TbApiClient client}) : _client = client;

  final TbApiClient _client;

  @override
  Future<List<TbAttributeEntry>> getAttributes(
    EntityId entityId,
    TbAttributeScope scope,
  ) async {
    final response = await _client.get<List<dynamic>>(
      '/api/plugins/telemetry/${entityId.entityType.wireValue}/${entityId.id}/values/attributes/${scope.wireValue}',
    );
    final list = response.data ?? const [];
    return list
        .whereType<Map<String, dynamic>>()
        .map((e) => TbAttributeEntry.fromJson(e, scope: scope))
        .toList(growable: false);
  }

  @override
  Future<void> saveAttributes(
    EntityId entityId,
    TbAttributeScope scope,
    Map<String, dynamic> attributes,
  ) async {
    await _client.post<void>(
      '/api/plugins/telemetry/${entityId.entityType.wireValue}/${entityId.id}/attributes/${scope.wireValue}',
      data: attributes,
    );
  }

  @override
  Future<void> deleteAttributes(
    EntityId entityId,
    TbAttributeScope scope,
    List<String> keys,
  ) async {
    await _client.delete<void>(
      '/api/plugins/telemetry/${entityId.entityType.wireValue}/${entityId.id}/${scope.wireValue}',
      queryParameters: <String, dynamic>{'keys': keys.join(',')},
    );
  }

  @override
  Future<Map<String, TbTsPoint>> getLatestTimeseries(
    EntityId entityId, {
    List<String>? keys,
  }) async {
    final response = await _client.get<Map<String, dynamic>>(
      '/api/plugins/telemetry/${entityId.entityType.wireValue}/${entityId.id}/values/timeseries',
      queryParameters: <String, dynamic>{
        if (keys != null && keys.isNotEmpty) 'keys': keys.join(','),
        'useStrictDataTypes': true,
      },
    );
    final parsed = _parseSeriesMap(response.data ?? const <String, dynamic>{});
    return <String, TbTsPoint>{
      for (final entry in parsed.entries)
        if (entry.value.isNotEmpty) entry.key: entry.value.first,
    };
  }

  @override
  Future<Map<String, List<TbTsPoint>>> getTimeseriesHistory(
    TbTsHistoryQuery query, {
    CancelToken? cancelToken,
  }) async {
    final baseParams = <String, dynamic>{
      if (query.keys.isNotEmpty) 'keys': query.keys.join(','),
      'startTs': query.startTs,
      'endTs': query.endTs,
      if (query.intervalMs > 0) 'interval': query.intervalMs,
      'limit': query.limit,
      'agg': query.agg.wireValue,
      'orderBy': 'ASC',
      'useStrictDataTypes': true,
    };

    final entityPath =
        '/api/plugins/telemetry/${query.entityId.entityType.wireValue}/${query.entityId.id}/values/timeseries';

    try {
      final response = await _client.get<Map<String, dynamic>>(
        '$entityPath/history',
        queryParameters: baseParams,
        cancelToken: cancelToken,
      );
      return _parseSeriesMap(response.data ?? const <String, dynamic>{});
    } on TbFailure catch (e) {
      // HTTP 404 ONLY fallback for pre-4.4 servers; never retry on 400/403.
      if (e.type != TbFailureType.notFound) rethrow;
      final fallback = await _client.get<Map<String, dynamic>>(
        entityPath,
        queryParameters: baseParams,
        cancelToken: cancelToken,
      );
      return _parseSeriesMap(fallback.data ?? const <String, dynamic>{});
    }
  }

  Map<String, List<TbTsPoint>> _parseSeriesMap(Map<String, dynamic> raw) {
    final out = <String, List<TbTsPoint>>{};
    for (final entry in raw.entries) {
      final list = entry.value as List<dynamic>? ?? const [];
      out[entry.key] = list
          .whereType<Map<String, dynamic>>()
          .map(TbTsPoint.fromJson)
          .toList(growable: false);
    }
    return out;
  }
}

final class DemoTelemetryRepository implements TelemetryRepository {
  DemoTelemetryRepository(List<MockDevice> devices)
    : _devices = devices,
      _attributes = {
        for (final entry in demoDeviceAttributes.entries)
          entry.key: {
            for (final scopeEntry in entry.value.entries)
              scopeEntry.key: List<TbAttributeEntry>.from(scopeEntry.value),
          },
      };

  final List<MockDevice> _devices;
  final Map<String, Map<TbAttributeScope, List<TbAttributeEntry>>> _attributes;

  @override
  Future<List<TbAttributeEntry>> getAttributes(
    EntityId entityId,
    TbAttributeScope scope,
  ) async {
    return List<TbAttributeEntry>.unmodifiable(
      _attributes[entityId.id]?[scope] ?? const [],
    );
  }

  @override
  Future<void> saveAttributes(
    EntityId entityId,
    TbAttributeScope scope,
    Map<String, dynamic> attributes,
  ) async {
    if (!scope.isWritableViaRest) {
      throw const TbFailure(
        type: TbFailureType.validation,
        message: 'Client scope attributes are read-only',
      );
    }
    final scopeMap = _attributes.putIfAbsent(entityId.id, () => {});
    final list = scopeMap.putIfAbsent(scope, () => []);
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final entry in attributes.entries) {
      list.removeWhere((a) => a.key == entry.key);
      list.add(
        TbAttributeEntry(
          key: entry.key,
          value: entry.value,
          lastUpdateTs: now,
          scope: scope,
        ),
      );
    }
  }

  @override
  Future<void> deleteAttributes(
    EntityId entityId,
    TbAttributeScope scope,
    List<String> keys,
  ) async {
    final list = _attributes[entityId.id]?[scope];
    list?.removeWhere((a) => keys.contains(a.key));
  }

  @override
  Future<Map<String, TbTsPoint>> getLatestTimeseries(
    EntityId entityId, {
    List<String>? keys,
  }) async {
    final dev = _devices.where((d) => d.id == entityId.id).firstOrNull;
    if (dev == null) return const {};
    final now = DateTime.now().millisecondsSinceEpoch;
    final out = <String, TbTsPoint>{};
    for (final entry in dev.telemetry.entries) {
      if (keys != null && keys.isNotEmpty && !keys.contains(entry.key)) {
        continue;
      }
      final numMatch = RegExp(r'-?\d+(?:\.\d+)?').firstMatch(entry.value);
      final numVal = numMatch != null
          ? double.tryParse(numMatch.group(0)!)
          : null;
      out[entry.key] = TbTsPoint(
        ts: now,
        rawValue: entry.value,
        numericValue: numVal,
      );
    }
    return out;
  }

  @override
  Future<Map<String, List<TbTsPoint>>> getTimeseriesHistory(
    TbTsHistoryQuery query, {
    CancelToken? cancelToken,
  }) async {
    final keys = query.keys.isNotEmpty
        ? query.keys
        : const ['temperature', 'humidity'];
    return buildDemoTelemetryHistory(
      keys: keys,
      startTs: query.startTs,
      endTs: query.endTs,
    );
  }
}
