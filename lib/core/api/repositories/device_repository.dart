import 'package:dio/dio.dart';
import 'package:thingsboard_democloud_app/core/api/client/tb_api_client.dart';
import 'package:thingsboard_democloud_app/core/mock/mock_data.dart';
import 'package:thingsboard_democloud_app/core/models/device_models.dart';
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
  RestDeviceRepository({required TbApiClient client}) : _client = client;

  final TbApiClient _client;

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
    try {
      final resp = await _client.post<num>(
        '/api/entitiesQuery/count',
        data: <String, dynamic>{
          'entityFilter': <String, dynamic>{
            'type': 'deviceType',
            'deviceTypes': <String>[profile.name],
            'deviceNameFilter': '',
          },
          'keyFilters': <Map<String, dynamic>>[
            <String, dynamic>{
              'key': const <String, dynamic>{
                'type': 'SERVER_ATTRIBUTE',
                'key': 'active',
              },
              'valueType': 'BOOLEAN',
              'predicate': <String, dynamic>{
                'type': 'BOOLEAN',
                'operation': 'EQUAL',
                'value': <String, dynamic>{'defaultValue': active},
              },
            },
          ],
        },
        cancelToken: cancelToken,
      );
      return resp.data?.toInt() ?? 0;
    } on TbFailure catch (e) {
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

  @override
  Future<PageData<TbDeviceInfo>> getDevices(
    PageQuery query,
    TbDeviceQuery filter, {
    CancelToken? cancelToken,
  }) async {
    final params = <String, dynamic>{
      ...query.toQueryParameters(),
      'includeCustomers': true,
      if (filter.deviceProfileId != null && filter.deviceProfileId!.isNotEmpty)
        'deviceProfileId': filter.deviceProfileId,
      if (filter.active != null) 'active': filter.active,
      if (filter.textSearch != null && filter.textSearch!.trim().isNotEmpty)
        'textSearch': filter.textSearch!.trim(),
    };
    try {
      final response = await _client.get<Map<String, dynamic>>(
        '/api/deviceInfos/all',
        queryParameters: params,
        cancelToken: cancelToken,
      );
      return PageData<TbDeviceInfo>.fromJson(
        response.data ?? const <String, dynamic>{},
        TbDeviceInfo.fromJson,
      );
    } on TbFailure catch (e) {
      if (e.type != TbFailureType.notFound) rethrow;
      final fallback = await _client.get<Map<String, dynamic>>(
        '/api/tenant/deviceInfos',
        queryParameters: params,
        cancelToken: cancelToken,
      );
      return PageData<TbDeviceInfo>.fromJson(
        fallback.data ?? const <String, dynamic>{},
        TbDeviceInfo.fromJson,
      );
    }
  }

  @override
  Future<TbDeviceInfo> getDeviceInfo(String deviceId) async {
    final response = await _client.get<Map<String, dynamic>>(
      '/api/device/info/$deviceId',
    );
    return TbDeviceInfo.fromJson(response.data ?? const <String, dynamic>{});
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
      // Device names are user-typed: encode so `/`, `?`, `#` cannot change the route.
      '/api/customer/device/${Uri.encodeComponent(deviceName)}/claim',
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
