import 'package:dio/dio.dart';
import 'package:thingsboard_democloud_app/core/api/client/tb_api_client.dart';
import 'package:thingsboard_democloud_app/core/mock/mock_data.dart';
import 'package:thingsboard_democloud_app/core/models/device_models.dart';
import 'package:thingsboard_democloud_app/core/models/entity_id.dart';
import 'package:thingsboard_democloud_app/core/models/pagination.dart';
import 'package:thingsboard_democloud_app/core/models/tb_failure.dart';

/// Device profiles (with active/inactive counts), devices, credentials, and claiming boundary.
abstract interface class DeviceRepository {
  Future<PageData<TbDeviceProfileSummary>> getDeviceProfiles(
    PageQuery query, {
    CancelToken? cancelToken,
  });

  Future<PageData<TbDeviceInfo>> getDevices(
    PageQuery query,
    TbDeviceQuery filter, {
    CancelToken? cancelToken,
  });

  Future<TbDeviceInfo> getDeviceInfo(String deviceId);
  Future<TbDeviceCredentials> getDeviceCredentials(String deviceId);
  Future<TbClaimResult> claimDevice(String deviceName, {String? secretKey});
}

final class RestDeviceRepository implements DeviceRepository {
  RestDeviceRepository({
    required TbApiClient client,
    ({Authority? authority, String? customerId}) Function()? userScopeProvider,
  }) : _client = client,
       _userScopeProvider = userScopeProvider;

  final TbApiClient _client;
  final ({Authority? authority, String? customerId}) Function()?
  _userScopeProvider;

  bool _peDeviceInfosAllUnsupported = false;
  bool _legacyDeviceTypeFilter = false;

  static Map<String, dynamic> _deviceTypeEntityFilter(
    String typeName,
    String nameFilter, {
    required bool legacy,
  }) => legacy
      ? <String, dynamic>{
          'type': 'deviceType',
          'deviceType': typeName,
          'deviceNameFilter': nameFilter,
        }
      : <String, dynamic>{
          'type': 'deviceType',
          'deviceTypes': <String>[typeName],
          'deviceNameFilter': nameFilter,
        };

  static bool _isBadRequestFilterError(TbFailure e) =>
      e.type == TbFailureType.validation || e.statusCode == 400;

  @override
  Future<PageData<TbDeviceProfileSummary>> getDeviceProfiles(
    PageQuery query, {
    CancelToken? cancelToken,
  }) async {
    final response = await _client.get<Map<String, dynamic>>(
      '/api/deviceProfileInfos',
      queryParameters: query.toQueryParameters(),
      cancelToken: cancelToken,
    );
    final rawPage = PageData<TbDeviceProfileSummary>.fromJson(
      response.data ?? const <String, dynamic>{},
      TbDeviceProfileSummary.fromJson,
    );

    final enriched = await Future.wait(
      rawPage.data.map((profile) async {
        final active = await _countDevicesForProfile(
          profile: profile,
          active: true,
          cancelToken: cancelToken,
        );
        final inactive = await _countDevicesForProfile(
          profile: profile,
          active: false,
          cancelToken: cancelToken,
        );
        return profile.copyWith(activeCount: active, inactiveCount: inactive);
      }),
    );

    return PageData<TbDeviceProfileSummary>(
      data: enriched,
      totalPages: rawPage.totalPages,
      totalElements: rawPage.totalElements,
      hasNext: rawPage.hasNext,
    );
  }

  Future<int> _countDevicesForProfile({
    required TbDeviceProfileSummary profile,
    required bool active,
    CancelToken? cancelToken,
  }) async {
    Future<Response<num>> postCount({required bool legacy}) {
      return _client.post<num>(
        '/api/entitiesQuery/count',
        data: <String, dynamic>{
          'entityFilter': _deviceTypeEntityFilter(
            profile.name,
            '',
            legacy: legacy,
          ),
          'keyFilters': <Map<String, dynamic>>[_activeKeyFilter(active)],
        },
        cancelToken: cancelToken,
      );
    }

    try {
      final resp = await postCount(legacy: _legacyDeviceTypeFilter);
      return resp.data?.toInt() ?? 0;
    } on TbFailure catch (e) {
      if (!_legacyDeviceTypeFilter && _isBadRequestFilterError(e)) {
        _legacyDeviceTypeFilter = true;
        final retryResp = await postCount(legacy: true);
        return retryResp.data?.toInt() ?? 0;
      }
      if (e.type != TbFailureType.notFound) rethrow;
      final fallback = await _client.get<Map<String, dynamic>>(
        '/api/deviceInfos/all',
        queryParameters: <String, dynamic>{
          'pageSize': 1,
          'page': 0,
          'deviceProfileId': profile.id,
          'active': active,
        },
        cancelToken: cancelToken,
      );
      return (fallback.data?['totalElements'] as num?)?.toInt() ?? 0;
    }
  }

  static Map<String, dynamic> _activeKeyFilter(
    bool active,
  ) => <String, dynamic>{
    'key': const <String, dynamic>{'type': 'SERVER_ATTRIBUTE', 'key': 'active'},
    'valueType': 'BOOLEAN',
    'predicate': <String, dynamic>{
      'type': 'BOOLEAN',
      'operation': 'EQUAL',
      'value': <String, dynamic>{'defaultValue': active},
    },
  };

  static bool _parseBoolWire(Object? raw) => switch (raw) {
    bool b => b,
    String s => s.toLowerCase() == 'true',
    _ => false,
  };

  @override
  Future<PageData<TbDeviceInfo>> getDevices(
    PageQuery query,
    TbDeviceQuery filter, {
    CancelToken? cancelToken,
  }) async {
    if (!_peDeviceInfosAllUnsupported) {
      final peParams = <String, dynamic>{
        ...query.toQueryParameters(),
        'includeCustomers': true,
        if (filter.deviceProfileId != null &&
            filter.deviceProfileId!.isNotEmpty)
          'deviceProfileId': filter.deviceProfileId,
        if (filter.active != null) 'active': filter.active,
        if (filter.textSearch != null && filter.textSearch!.trim().isNotEmpty)
          'textSearch': filter.textSearch!.trim(),
      };
      try {
        final response = await _client.get<Map<String, dynamic>>(
          '/api/deviceInfos/all',
          queryParameters: peParams,
          cancelToken: cancelToken,
        );
        final page = PageData<TbDeviceInfo>.fromJson(
          response.data ?? const <String, dynamic>{},
          TbDeviceInfo.fromJson,
        );
        if (filter.deviceType != null &&
            filter.deviceType!.isNotEmpty &&
            (filter.deviceProfileId == null ||
                filter.deviceProfileId!.isEmpty)) {
          final matching = page.data
              .where((d) => d.type == filter.deviceType)
              .toList(growable: false);
          return PageData<TbDeviceInfo>(
            data: matching,
            totalPages: page.totalPages,
            totalElements: matching.length,
            hasNext: page.hasNext,
          );
        }
        return page;
      } on TbFailure catch (e) {
        if (e.type != TbFailureType.notFound) rethrow;
        _peDeviceInfosAllUnsupported = true;
      }
    }

    // On pre-4.x servers where `/api/deviceInfos/all` is absent and `active`
    // is filtered explicitly, query `/api/entitiesQuery/find` so server-side
    // `SERVER_ATTRIBUTE.active` filtering and `active` state work accurately.
    if (filter.active != null) {
      return _findDevicesByEntityQuery(
        query: query,
        filter: filter,
        cancelToken: cancelToken,
      );
    }

    final scope = _userScopeProvider?.call();
    final customerId = scope?.customerId;
    final useCustomerPath =
        scope?.authority == Authority.customerUser &&
        customerId != null &&
        customerId.isNotEmpty &&
        customerId != TbDeviceInfo.nullUuid;

    final fallbackPath = useCustomerPath
        ? '/api/customer/$customerId/deviceInfos'
        : '/api/tenant/deviceInfos';

    final hasProfileId =
        filter.deviceProfileId != null && filter.deviceProfileId!.isNotEmpty;
    final hasDeviceType =
        filter.deviceType != null && filter.deviceType!.isNotEmpty;
    final search = (filter.textSearch ?? query.textSearch ?? '').trim();

    final fallbackParams = <String, dynamic>{
      ...query.toQueryParameters(),
      if (search.isNotEmpty) 'textSearch': search,
      if (hasProfileId)
        'deviceProfileId': filter.deviceProfileId
      else if (hasDeviceType)
        'type': filter.deviceType
      else
        'deviceProfileId': '',
    };

    final fallback = await _client.get<Map<String, dynamic>>(
      fallbackPath,
      queryParameters: fallbackParams,
      cancelToken: cancelToken,
    );
    return _parseAndEnrichDevicePage(
      fallback.data ?? const <String, dynamic>{},
      cancelToken: cancelToken,
    );
  }

  /// Direct `GET /api/tenant/deviceInfos` (falls back to `GET /api/tenant/devices` on PE 4.4 404).
  Future<PageData<TbDeviceInfo>> getTenantDeviceInfos(
    PageQuery query, {
    String? deviceProfileId,
    String? type,
    CancelToken? cancelToken,
  }) async {
    final hasProfile = deviceProfileId != null && deviceProfileId.isNotEmpty;
    final hasType = type != null && type.isNotEmpty;
    final params = <String, dynamic>{
      ...query.toQueryParameters(),
      if (hasProfile)
        'deviceProfileId': deviceProfileId
      else if (hasType)
        'type': type
      else
        'deviceProfileId': '',
    };
    try {
      final response = await _client.get<Map<String, dynamic>>(
        '/api/tenant/deviceInfos',
        queryParameters: params,
        cancelToken: cancelToken,
      );
      return _parseAndEnrichDevicePage(
        response.data ?? const <String, dynamic>{},
        cancelToken: cancelToken,
      );
    } on TbFailure catch (e) {
      if (e.type != TbFailureType.notFound) rethrow;
      return getTenantDevices(query, type: type, cancelToken: cancelToken);
    }
  }

  /// Direct `GET /api/tenant/devices`.
  Future<PageData<TbDeviceInfo>> getTenantDevices(
    PageQuery query, {
    String? type,
    CancelToken? cancelToken,
  }) async {
    final response = await _client.get<Map<String, dynamic>>(
      '/api/tenant/devices',
      queryParameters: <String, dynamic>{
        ...query.toQueryParameters(),
        if (type != null && type.isNotEmpty) 'type': type,
      },
      cancelToken: cancelToken,
    );
    return _parseAndEnrichDevicePage(
      response.data ?? const <String, dynamic>{},
      cancelToken: cancelToken,
    );
  }

  /// Direct `GET /api/tenant/device?deviceName=...` (PE 4.4) with fallback to
  /// `GET /api/tenant/devices?deviceName=...` (TB 3.3).
  Future<TbDeviceInfo> getTenantDeviceByName(String deviceName) async {
    final params = <String, dynamic>{'deviceName': deviceName};
    try {
      final response = await _client.get<Map<String, dynamic>>(
        '/api/tenant/device',
        queryParameters: params,
      );
      return TbDeviceInfo.fromJson(response.data ?? const <String, dynamic>{});
    } on TbFailure catch (e) {
      if (e.type != TbFailureType.notFound) rethrow;
      final fallback = await _client.get<Map<String, dynamic>>(
        '/api/tenant/devices',
        queryParameters: params,
      );
      return TbDeviceInfo.fromJson(fallback.data ?? const <String, dynamic>{});
    }
  }

  /// Direct `POST /api/tenant/{tenantId}/device/{deviceId}` (assign device to tenant).
  Future<TbDeviceInfo> assignDeviceToTenant(
    String tenantId,
    String deviceId,
  ) async {
    final response = await _client.post<Map<String, dynamic>>(
      '/api/tenant/${tenantId.trim()}/device/${deviceId.trim()}',
    );
    return TbDeviceInfo.fromJson(response.data ?? const <String, dynamic>{});
  }

  Future<PageData<TbDeviceInfo>> _parseAndEnrichDevicePage(
    Map<String, dynamic> rawMap, {
    CancelToken? cancelToken,
  }) async {
    final rawItems = rawMap['data'] as List<dynamic>? ?? const <dynamic>[];
    final parsedPage = PageData<TbDeviceInfo>.fromJson(
      rawMap,
      TbDeviceInfo.fromJson,
    );

    final missingActiveField =
        parsedPage.data.isNotEmpty &&
        rawItems.whereType<Map<String, dynamic>>().any(
          (m) => !m.containsKey('active'),
        );
    if (!missingActiveField) {
      return parsedPage;
    }

    final enrichedItems = await _enrichMissingActiveFlags(
      parsedPage.data,
      cancelToken: cancelToken,
    );
    return PageData<TbDeviceInfo>(
      data: enrichedItems,
      totalPages: parsedPage.totalPages,
      totalElements: parsedPage.totalElements,
      hasNext: parsedPage.hasNext,
    );
  }

  Future<PageData<TbDeviceInfo>> _findDevicesByEntityQuery({
    required PageQuery query,
    required TbDeviceQuery filter,
    CancelToken? cancelToken,
  }) async {
    final search = (filter.textSearch ?? query.textSearch ?? '').trim();
    final hasType = filter.deviceType != null && filter.deviceType!.isNotEmpty;

    Future<Response<Map<String, dynamic>>> postFind({required bool legacy}) {
      final entityFilter = hasType
          ? _deviceTypeEntityFilter(
              filter.deviceType!,
              search,
              legacy: legacy,
            )
          : <String, dynamic>{'type': 'entityType', 'entityType': 'DEVICE'};
      return _client.post<Map<String, dynamic>>(
        '/api/entitiesQuery/find',
        data: <String, dynamic>{
          'entityFilter': entityFilter,
          if (filter.active != null)
            'keyFilters': <Map<String, dynamic>>[
              _activeKeyFilter(filter.active!),
            ],
          'entityFields': const <Map<String, dynamic>>[
            {'type': 'ENTITY_FIELD', 'key': 'name'},
            {'type': 'ENTITY_FIELD', 'key': 'type'},
            {'type': 'ENTITY_FIELD', 'key': 'label'},
            {'type': 'ENTITY_FIELD', 'key': 'createdTime'},
          ],
          'latestValues': const <Map<String, dynamic>>[
            {'type': 'SERVER_ATTRIBUTE', 'key': 'active'},
          ],
          'pageLink': <String, dynamic>{
            'pageSize': query.pageSize,
            'page': query.page,
            if (search.isNotEmpty) 'textSearch': search,
          },
        },
        cancelToken: cancelToken,
      );
    }

    Response<Map<String, dynamic>> response;
    try {
      response = await postFind(legacy: _legacyDeviceTypeFilter);
    } on TbFailure catch (e) {
      if (hasType && !_legacyDeviceTypeFilter && _isBadRequestFilterError(e)) {
        _legacyDeviceTypeFilter = true;
        response = await postFind(legacy: true);
      } else {
        rethrow;
      }
    }

    final raw = response.data ?? const <String, dynamic>{};
    final rows = raw['data'] as List<dynamic>? ?? const <dynamic>[];
    final items = <TbDeviceInfo>[];
    for (final row in rows.whereType<Map<String, dynamic>>()) {
      final entityId = EntityId.maybeFromJson(row['entityId']);
      if (entityId == null) continue;
      final latest = row['latest'] as Map<String, dynamic>? ?? const {};
      final fields =
          latest['ENTITY_FIELD'] as Map<String, dynamic>? ?? const {};
      final serverAttrs =
          latest['SERVER_ATTRIBUTE'] as Map<String, dynamic>? ?? const {};
      String fieldStr(String key) =>
          (fields[key] as Map<String, dynamic>?)?['value']?.toString() ?? '';
      final activeVal =
          (serverAttrs['active'] as Map<String, dynamic>?)?['value'];
      final createdRaw = fieldStr('createdTime');

      items.add(
        TbDeviceInfo(
          id: entityId.id,
          name: fieldStr('name'),
          type: fieldStr('type'),
          label: fieldStr('label'),
          deviceProfileId: filter.deviceProfileId,
          active: activeVal != null
              ? _parseBoolWire(activeVal)
              : (filter.active ?? false),
          createdTime: int.tryParse(createdRaw) ?? 0,
        ),
      );
    }

    return PageData<TbDeviceInfo>(
      data: items,
      totalPages: (raw['totalPages'] as num?)?.toInt() ?? 0,
      totalElements: (raw['totalElements'] as num?)?.toInt() ?? items.length,
      hasNext: raw['hasNext'] as bool? ?? false,
    );
  }

  Future<List<TbDeviceInfo>> _enrichMissingActiveFlags(
    List<TbDeviceInfo> items, {
    CancelToken? cancelToken,
  }) async {
    try {
      final ids = items.map((d) => d.id).where((id) => id.isNotEmpty).toList();
      if (ids.isEmpty) return items;

      final response = await _client.post<Map<String, dynamic>>(
        '/api/entitiesQuery/find',
        data: <String, dynamic>{
          'entityFilter': <String, dynamic>{
            'type': 'entityList',
            'entityType': 'DEVICE',
            'entityList': ids,
          },
          'latestValues': const <Map<String, dynamic>>[
            {'type': 'SERVER_ATTRIBUTE', 'key': 'active'},
          ],
          'pageLink': <String, dynamic>{'pageSize': ids.length, 'page': 0},
        },
        cancelToken: cancelToken,
      );

      final rows =
          (response.data?['data'] as List<dynamic>?) ?? const <dynamic>[];
      final activeById = <String, bool>{};
      for (final row in rows.whereType<Map<String, dynamic>>()) {
        final id = EntityId.maybeFromJson(row['entityId'])?.id;
        if (id == null) continue;
        final latest = row['latest'] as Map<String, dynamic>?;
        final serverAttr = latest?['SERVER_ATTRIBUTE'] as Map<String, dynamic>?;
        final rawVal =
            (serverAttr?['active'] as Map<String, dynamic>?)?['value'];
        if (rawVal != null) {
          activeById[id] = _parseBoolWire(rawVal);
        }
      }
      if (activeById.isEmpty) return items;
      return [
        for (final item in items)
          activeById.containsKey(item.id)
              ? item.copyWith(active: activeById[item.id])
              : item,
      ];
    } catch (_) {
      return items;
    }
  }

  @override
  Future<TbDeviceInfo> getDeviceInfo(String deviceId) async {
    final response = await _client.get<Map<String, dynamic>>(
      '/api/device/info/$deviceId',
    );
    final data = response.data ?? const <String, dynamic>{};
    final info = TbDeviceInfo.fromJson(data);
    if (data.containsKey('active')) {
      return info;
    }

    try {
      final attrResp = await _client.get<List<dynamic>>(
        '/api/plugins/telemetry/DEVICE/$deviceId/values/attributes/SERVER_SCOPE',
        queryParameters: const <String, dynamic>{'keys': 'active'},
      );
      for (final raw in attrResp.data ?? const <dynamic>[]) {
        if (raw is Map<String, dynamic> && raw['key'] == 'active') {
          return info.copyWith(active: _parseBoolWire(raw['value']));
        }
      }
    } catch (_) {
      // Best-effort attribute lookup on pre-3.4 servers.
    }
    return info;
  }

  @override
  Future<TbDeviceCredentials> getDeviceCredentials(String deviceId) async {
    final response = await _client.get<Map<String, dynamic>>(
      '/api/device/$deviceId/credentials',
    );
    return TbDeviceCredentials.fromJson(
      response.data ?? const <String, dynamic>{},
    );
  }

  @override
  Future<TbClaimResult> claimDevice(
    String deviceName, {
    String? secretKey,
  }) async {
    final response = await _client.post<Map<String, dynamic>>(
      '/api/customer/device/$deviceName/claim',
      data: <String, dynamic>{
        if (secretKey != null && secretKey.isNotEmpty) 'secretKey': secretKey,
      },
    );
    return TbClaimResult.fromJson(response.data ?? const <String, dynamic>{});
  }
}

final class DemoDeviceRepository implements DeviceRepository {
  DemoDeviceRepository(List<MockDevice> devices)
    : _devices = [
        for (final d in devices)
          TbDeviceInfo(
            id: d.id,
            name: d.name,
            type: d.type,
            label: d.label,
            deviceProfileId: _profileIdForType(d.type),
            active: d.active,
            ownerName: d.customerName,
            createdTime: d.createdTime.millisecondsSinceEpoch,
            telemetry: d.telemetry,
          ),
      ];

  final List<TbDeviceInfo> _devices;

  static String _profileIdForType(String type) => switch (type) {
    'Thermostat' => 'dp-1',
    'Energy Meter' => 'dp-2',
    'GPS Tracker' => 'dp-3',
    'Water Sensor' => 'dp-4',
    _ => 'dp-1',
  };

  @override
  Future<PageData<TbDeviceProfileSummary>> getDeviceProfiles(
    PageQuery query, {
    CancelToken? cancelToken,
  }) async {
    const defs = [
      (id: 'dp-1', name: 'Thermostat'),
      (id: 'dp-2', name: 'Energy Meter'),
      (id: 'dp-3', name: 'GPS Tracker'),
      (id: 'dp-4', name: 'Water Sensor'),
    ];
    final search = query.textSearch?.trim().toLowerCase() ?? '';
    final list = [
      for (final def in defs)
        if (search.isEmpty || def.name.toLowerCase().contains(search))
          TbDeviceProfileSummary(
            id: def.id,
            name: def.name,
            activeCount: _devices
                .where((d) => d.type == def.name && d.active)
                .length,
            inactiveCount: _devices
                .where((d) => d.type == def.name && !d.active)
                .length,
          ),
    ];
    return PageData<TbDeviceProfileSummary>(
      data: list,
      totalPages: 1,
      totalElements: list.length,
      hasNext: false,
    );
  }

  @override
  Future<PageData<TbDeviceInfo>> getDevices(
    PageQuery query,
    TbDeviceQuery filter, {
    CancelToken? cancelToken,
  }) async {
    final search = (filter.textSearch ?? query.textSearch ?? '')
        .trim()
        .toLowerCase();
    final filtered = _devices
        .where((d) {
          if (filter.deviceProfileId != null &&
              filter.deviceProfileId!.isNotEmpty &&
              d.deviceProfileId != filter.deviceProfileId) {
            return false;
          }
          if (filter.deviceType != null &&
              filter.deviceType!.isNotEmpty &&
              d.type != filter.deviceType) {
            return false;
          }
          if (filter.active != null && d.active != filter.active) return false;
          if (search.isNotEmpty &&
              !d.name.toLowerCase().contains(search) &&
              !d.label.toLowerCase().contains(search) &&
              !d.type.toLowerCase().contains(search)) {
            return false;
          }
          return true;
        })
        .toList(growable: false);

    final start = query.page * query.pageSize;
    if (start >= filtered.length) {
      return PageData<TbDeviceInfo>(
        data: const [],
        totalPages: (filtered.length / query.pageSize).ceil(),
        totalElements: filtered.length,
        hasNext: false,
      );
    }
    final end = (start + query.pageSize).clamp(0, filtered.length);
    return PageData<TbDeviceInfo>(
      data: filtered.sublist(start, end),
      totalPages: (filtered.length / query.pageSize).ceil(),
      totalElements: filtered.length,
      hasNext: end < filtered.length,
    );
  }

  @override
  Future<TbDeviceInfo> getDeviceInfo(String deviceId) async {
    return _devices.firstWhere(
      (d) => d.id == deviceId,
      orElse: () => throw const TbFailure(
        type: TbFailureType.notFound,
        message: 'Device not found',
      ),
    );
  }

  @override
  Future<TbDeviceCredentials> getDeviceCredentials(String deviceId) async {
    return TbDeviceCredentials(
      id: 'cred-$deviceId',
      deviceId: deviceId,
      credentialsType: 'ACCESS_TOKEN',
      credentialsId: 'demo-token-$deviceId',
    );
  }

  @override
  Future<TbClaimResult> claimDevice(
    String deviceName, {
    String? secretKey,
  }) async {
    return TbClaimResult(response: 'CLAIMED', device: _devices.first);
  }
}
