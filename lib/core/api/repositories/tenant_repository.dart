import 'package:dio/dio.dart';
import 'package:thingsboard_democloud_app/core/api/client/tb_api_client.dart';
import 'package:thingsboard_democloud_app/core/models/asset_models.dart';
import 'package:thingsboard_democloud_app/core/models/customer_models.dart';
import 'package:thingsboard_democloud_app/core/models/dashboard_models.dart';
import 'package:thingsboard_democloud_app/core/models/device_models.dart';
import 'package:thingsboard_democloud_app/core/models/entity_id.dart';
import 'package:thingsboard_democloud_app/core/models/pagination.dart';
import 'package:thingsboard_democloud_app/core/models/tb_failure.dart';
import 'package:thingsboard_democloud_app/core/models/tenant_models.dart';
import 'package:thingsboard_democloud_app/core/models/user_models.dart';

/// Unified boundary for ThingsBoard `tenant-controller`, `tenant-profile-controller`,
/// and tenant-scoped `/api/tenant/*` endpoints across PE 4.4.x and TB 3.3.x.
abstract interface class TenantRepository {
  // Tenant CRUD & Listing (`tenant-controller`)
  Future<TbTenantInfo> getTenantInfo(String tenantId);
  Future<TbTenantInfo> getTenantById(String tenantId);
  Future<TbTenantInfo> saveTenant(TbTenantInfo tenant);
  Future<void> deleteTenant(String tenantId);
  Future<PageData<TbTenantInfo>> getTenantInfos(
    PageQuery query, {
    CancelToken? cancelToken,
  });
  Future<PageData<TbTenantInfo>> getTenants(
    PageQuery query, {
    CancelToken? cancelToken,
  });
  Future<List<TbTenantInfo>> getTenantsByIds(List<String> tenantIds);

  // Tenant Profiles (`tenant-profile-controller`)
  Future<TbTenantProfileInfo?> getDefaultTenantProfileInfo();
  Future<TbTenantProfileInfo> getTenantProfileInfo(String tenantProfileId);
  Future<TbTenantProfileInfo> getTenantProfileById(String tenantProfileId);
  Future<PageData<TbTenantProfileInfo>> getTenantProfileInfos(
    PageQuery query, {
    CancelToken? cancelToken,
  });
  Future<PageData<TbTenantProfileInfo>> getTenantProfiles(
    PageQuery query, {
    CancelToken? cancelToken,
  });
  Future<List<TbTenantProfileInfo>> getTenantProfilesByIds(List<String> ids);
  Future<TbTenantProfileInfo> saveTenantProfile(TbTenantProfileInfo profile);
  Future<TbTenantProfileInfo> setDefaultTenantProfile(String tenantProfileId);
  Future<void> deleteTenantProfile(String tenantProfileId);

  // Tenant Users, Home Dashboard, Subscription & Queues
  Future<PageData<TbUserProfile>> getTenantUsers(
    String tenantId,
    PageQuery query, {
    CancelToken? cancelToken,
  });
  Future<TbHomeDashboardInfo?> getTenantHomeDashboardInfo();
  Future<void> setTenantHomeDashboardInfo(TbHomeDashboardInfo info);
  Future<TbTenantSubscriptionSummary?> getSubscriptionSummary();
  Future<List<Map<String, dynamic>>> getTenantQueues({
    String serviceType = 'TB_RULE_ENGINE',
  });

  // Tenant Entity Views & Edges (`/api/tenant/entityViews*`, `/api/tenant/edges*`)
  Future<PageData<TbEntityViewInfo>> getTenantEntityViews(
    PageQuery query, {
    String? type,
    CancelToken? cancelToken,
  });
  Future<TbEntityViewInfo> getTenantEntityViewByName(String entityViewName);

  Future<PageData<TbEdgeInfo>> getTenantEdges(
    PageQuery query, {
    String? type,
    CancelToken? cancelToken,
  });
  Future<TbEdgeInfo> getTenantEdgeByName(String edgeName);

  // Direct `/api/tenant/*` Device, Asset, Customer & Dashboard helpers
  Future<PageData<TbDeviceInfo>> getTenantDeviceInfos(
    PageQuery query, {
    String? deviceProfileId,
    String? type,
    CancelToken? cancelToken,
  });
  Future<PageData<TbDeviceInfo>> getTenantDevices(
    PageQuery query, {
    String? type,
    CancelToken? cancelToken,
  });
  Future<TbDeviceInfo> getTenantDeviceByName(String deviceName);
  Future<TbDeviceInfo> assignDeviceToTenant(String tenantId, String deviceId);

  Future<PageData<TbAssetInfo>> getTenantAssetInfos(
    PageQuery query, {
    String? type,
    CancelToken? cancelToken,
  });
  Future<PageData<TbAssetInfo>> getTenantAssets(
    PageQuery query, {
    String? type,
    CancelToken? cancelToken,
  });
  Future<TbAssetInfo> getTenantAssetByName(String assetName);

  Future<TbCustomerInfo> getTenantCustomerByTitle(String customerTitle);

  Future<PageData<TbDashboardInfo>> getTenantDashboards(
    PageQuery query, {
    bool? mobile,
    CancelToken? cancelToken,
  });
  Future<PageData<TbDashboardInfo>> getTenantDashboardsByTenantId(
    String tenantId,
    PageQuery query, {
    CancelToken? cancelToken,
  });
}

final class RestTenantRepository implements TenantRepository {
  RestTenantRepository({required TbApiClient client}) : _client = client;

  final TbApiClient _client;

  @override
  Future<TbTenantInfo> getTenantInfo(String tenantId) async {
    final cleanId = tenantId.trim();
    try {
      final response = await _client.get<Map<String, dynamic>>(
        '/api/tenant/info/$cleanId',
      );
      return TbTenantInfo.fromJson(response.data ?? const <String, dynamic>{});
    } on TbFailure catch (e) {
      if (e.type != TbFailureType.notFound) rethrow;
      return getTenantById(cleanId);
    }
  }

  @override
  Future<TbTenantInfo> getTenantById(String tenantId) async {
    final response = await _client.get<Map<String, dynamic>>(
      '/api/tenant/${tenantId.trim()}',
    );
    return TbTenantInfo.fromJson(response.data ?? const <String, dynamic>{});
  }

  @override
  Future<TbTenantInfo> saveTenant(TbTenantInfo tenant) async {
    final response = await _client.post<Map<String, dynamic>>(
      '/api/tenant',
      data: tenant.toTenantPayload(),
    );
    return TbTenantInfo.fromJson(response.data ?? const <String, dynamic>{});
  }

  @override
  Future<void> deleteTenant(String tenantId) async {
    await _client.delete<void>('/api/tenant/${tenantId.trim()}');
  }

  @override
  Future<PageData<TbTenantInfo>> getTenantInfos(
    PageQuery query, {
    CancelToken? cancelToken,
  }) async {
    try {
      final response = await _client.get<Map<String, dynamic>>(
        '/api/tenantInfos',
        queryParameters: query.toQueryParameters(),
        cancelToken: cancelToken,
      );
      return PageData<TbTenantInfo>.fromJson(
        response.data ?? const <String, dynamic>{},
        TbTenantInfo.fromJson,
      );
    } on TbFailure catch (e) {
      if (e.type != TbFailureType.notFound) rethrow;
      return getTenants(query, cancelToken: cancelToken);
    }
  }

  @override
  Future<PageData<TbTenantInfo>> getTenants(
    PageQuery query, {
    CancelToken? cancelToken,
  }) async {
    final response = await _client.get<Map<String, dynamic>>(
      '/api/tenants',
      queryParameters: query.toQueryParameters(),
      cancelToken: cancelToken,
    );
    return PageData<TbTenantInfo>.fromJson(
      response.data ?? const <String, dynamic>{},
      TbTenantInfo.fromJson,
    );
  }

  @override
  Future<List<TbTenantInfo>> getTenantsByIds(List<String> tenantIds) async {
    final clean = tenantIds
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toList(growable: false);
    if (clean.isEmpty) return const [];
    try {
      final response = await _client.get<List<dynamic>>(
        '/api/tenants/list',
        queryParameters: <String, dynamic>{'tenantIds': clean.join(',')},
      );
      return (response.data ?? const <dynamic>[])
          .whereType<Map<String, dynamic>>()
          .map(TbTenantInfo.fromJson)
          .toList(growable: false);
    } on TbFailure catch (e) {
      if (e.type != TbFailureType.notFound) rethrow;
      return Future.wait(clean.map(getTenantById));
    }
  }

  @override
  Future<TbTenantProfileInfo?> getDefaultTenantProfileInfo() async {
    try {
      final response = await _client.get<Map<String, dynamic>>(
        '/api/tenantProfileInfo/default',
      );
      final data = response.data;
      return data != null ? TbTenantProfileInfo.fromJson(data) : null;
    } on TbFailure catch (e) {
      if (e.type == TbFailureType.notFound) return null;
      rethrow;
    }
  }

  @override
  Future<TbTenantProfileInfo> getTenantProfileInfo(
    String tenantProfileId,
  ) async {
    final response = await _client.get<Map<String, dynamic>>(
      '/api/tenantProfileInfo/${tenantProfileId.trim()}',
    );
    return TbTenantProfileInfo.fromJson(
      response.data ?? const <String, dynamic>{},
    );
  }

  @override
  Future<TbTenantProfileInfo> getTenantProfileById(
    String tenantProfileId,
  ) async {
    final response = await _client.get<Map<String, dynamic>>(
      '/api/tenantProfile/${tenantProfileId.trim()}',
    );
    return TbTenantProfileInfo.fromJson(
      response.data ?? const <String, dynamic>{},
    );
  }

  @override
  Future<PageData<TbTenantProfileInfo>> getTenantProfileInfos(
    PageQuery query, {
    CancelToken? cancelToken,
  }) async {
    try {
      final response = await _client.get<Map<String, dynamic>>(
        '/api/tenantProfileInfos',
        queryParameters: query.toQueryParameters(),
        cancelToken: cancelToken,
      );
      return PageData<TbTenantProfileInfo>.fromJson(
        response.data ?? const <String, dynamic>{},
        TbTenantProfileInfo.fromJson,
      );
    } on TbFailure catch (e) {
      if (e.type != TbFailureType.notFound) rethrow;
      return getTenantProfiles(query, cancelToken: cancelToken);
    }
  }

  @override
  Future<PageData<TbTenantProfileInfo>> getTenantProfiles(
    PageQuery query, {
    CancelToken? cancelToken,
  }) async {
    final response = await _client.get<Map<String, dynamic>>(
      '/api/tenantProfiles',
      queryParameters: query.toQueryParameters(),
      cancelToken: cancelToken,
    );
    return PageData<TbTenantProfileInfo>.fromJson(
      response.data ?? const <String, dynamic>{},
      TbTenantProfileInfo.fromJson,
    );
  }

  @override
  Future<List<TbTenantProfileInfo>> getTenantProfilesByIds(
    List<String> ids,
  ) async {
    final clean = ids
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toList(growable: false);
    if (clean.isEmpty) return const [];
    try {
      final response = await _client.get<List<dynamic>>(
        '/api/tenantProfiles/list',
        queryParameters: <String, dynamic>{'ids': clean.join(',')},
      );
      return (response.data ?? const <dynamic>[])
          .whereType<Map<String, dynamic>>()
          .map(TbTenantProfileInfo.fromJson)
          .toList(growable: false);
    } on TbFailure catch (e) {
      if (e.type != TbFailureType.notFound) rethrow;
      return Future.wait(clean.map(getTenantProfileInfo));
    }
  }

  @override
  Future<TbTenantProfileInfo> saveTenantProfile(
    TbTenantProfileInfo profile,
  ) async {
    final response = await _client.post<Map<String, dynamic>>(
      '/api/tenantProfile',
      data: profile.toPayload(),
    );
    return TbTenantProfileInfo.fromJson(
      response.data ?? const <String, dynamic>{},
    );
  }

  @override
  Future<TbTenantProfileInfo> setDefaultTenantProfile(
    String tenantProfileId,
  ) async {
    final response = await _client.post<Map<String, dynamic>>(
      '/api/tenantProfile/${tenantProfileId.trim()}/default',
    );
    return TbTenantProfileInfo.fromJson(
      response.data ?? const <String, dynamic>{},
    );
  }

  @override
  Future<void> deleteTenantProfile(String tenantProfileId) async {
    await _client.delete<void>('/api/tenantProfile/${tenantProfileId.trim()}');
  }

  @override
  Future<PageData<TbUserProfile>> getTenantUsers(
    String tenantId,
    PageQuery query, {
    CancelToken? cancelToken,
  }) async {
    final response = await _client.get<Map<String, dynamic>>(
      '/api/tenant/${tenantId.trim()}/users',
      queryParameters: query.toQueryParameters(),
      cancelToken: cancelToken,
    );
    return PageData<TbUserProfile>.fromJson(
      response.data ?? const <String, dynamic>{},
      TbUserProfile.fromJson,
    );
  }

  @override
  Future<TbHomeDashboardInfo?> getTenantHomeDashboardInfo() async {
    try {
      final response = await _client.get<Map<String, dynamic>>(
        '/api/tenant/dashboard/home/info',
      );
      final data = response.data;
      return data != null ? TbHomeDashboardInfo.fromJson(data) : null;
    } on TbFailure catch (e) {
      if (e.type == TbFailureType.notFound) return null;
      rethrow;
    }
  }

  @override
  Future<void> setTenantHomeDashboardInfo(TbHomeDashboardInfo info) async {
    await _client.post<void>(
      '/api/tenant/dashboard/home/info',
      data: info.toJson(),
    );
  }

  @override
  Future<TbTenantSubscriptionSummary?> getSubscriptionSummary() async {
    Map<String, dynamic>? subMap;
    try {
      final resp = await _client.get<Map<String, dynamic>>(
        '/api/tenant/subscription',
      );
      subMap = resp.data;
    } on TbFailure catch (e) {
      if (e.type == TbFailureType.notFound) return null;
      rethrow;
    }

    if (subMap == null) return null;

    Map<String, dynamic> usageMap = const {};
    Map<String, dynamic> mergedConfig = const {};
    var trendzUsed = false;
    var whiteLabelAllowed = false;

    try {
      final u = await _client.get<Map<String, dynamic>>(
        '/api/tenant/subscription/usage',
      );
      usageMap = u.data ?? const {};
    } catch (_) {}

    try {
      final m = await _client.get<Map<String, dynamic>>(
        '/api/tenant/subscription/mergedProfileConfig',
      );
      mergedConfig = m.data ?? const {};
    } catch (_) {}

    try {
      final t = await _client.get<bool>('/api/tenant/subscription/trendzUsed');
      trendzUsed = t.data ?? false;
    } catch (_) {}

    try {
      final w = await _client.get<bool>('/api/tenant/whiteLabelingAllowed');
      whiteLabelAllowed = w.data ?? false;
    } catch (_) {}

    return TbTenantSubscriptionSummary(
      planName: subMap['plan'] as String? ?? subMap['planName'] as String?,
      state: subMap['state'] as String? ?? subMap['status'] as String?,
      usage: usageMap,
      mergedProfileConfig: mergedConfig,
      trendzUsed: trendzUsed,
      whiteLabelingAllowed: whiteLabelAllowed,
    );
  }

  @override
  Future<List<Map<String, dynamic>>> getTenantQueues({
    String serviceType = 'TB_RULE_ENGINE',
  }) async {
    try {
      final response = await _client.get<List<dynamic>>(
        '/api/tenant/queues',
        queryParameters: <String, dynamic>{'serviceType': serviceType},
      );
      return (response.data ?? const <dynamic>[])
          .whereType<Map<String, dynamic>>()
          .toList(growable: false);
    } on TbFailure catch (e) {
      if (e.type == TbFailureType.notFound) return const [];
      rethrow;
    }
  }

  @override
  Future<PageData<TbEntityViewInfo>> getTenantEntityViews(
    PageQuery query, {
    String? type,
    CancelToken? cancelToken,
  }) async {
    final params = <String, dynamic>{
      ...query.toQueryParameters(),
      if (type != null && type.isNotEmpty) 'type': type,
    };
    try {
      final response = await _client.get<Map<String, dynamic>>(
        '/api/tenant/entityViewInfos',
        queryParameters: params,
        cancelToken: cancelToken,
      );
      return PageData<TbEntityViewInfo>.fromJson(
        response.data ?? const <String, dynamic>{},
        TbEntityViewInfo.fromJson,
      );
    } on TbFailure catch (e) {
      if (e.type != TbFailureType.notFound) rethrow;
      final fallback = await _client.get<Map<String, dynamic>>(
        '/api/tenant/entityViews',
        queryParameters: params,
        cancelToken: cancelToken,
      );
      return PageData<TbEntityViewInfo>.fromJson(
        fallback.data ?? const <String, dynamic>{},
        TbEntityViewInfo.fromJson,
      );
    }
  }

  @override
  Future<TbEntityViewInfo> getTenantEntityViewByName(
    String entityViewName,
  ) async {
    final queryParams = <String, dynamic>{'entityViewName': entityViewName};
    try {
      final response = await _client.get<Map<String, dynamic>>(
        '/api/tenant/entityView',
        queryParameters: queryParams,
      );
      return TbEntityViewInfo.fromJson(
        response.data ?? const <String, dynamic>{},
      );
    } on TbFailure catch (e) {
      if (e.type != TbFailureType.notFound) rethrow;
      final fallback = await _client.get<Map<String, dynamic>>(
        '/api/tenant/entityViews',
        queryParameters: queryParams,
      );
      return TbEntityViewInfo.fromJson(
        fallback.data ?? const <String, dynamic>{},
      );
    }
  }

  @override
  Future<PageData<TbEdgeInfo>> getTenantEdges(
    PageQuery query, {
    String? type,
    CancelToken? cancelToken,
  }) async {
    final params = <String, dynamic>{
      ...query.toQueryParameters(),
      if (type != null && type.isNotEmpty) 'type': type,
    };
    try {
      final response = await _client.get<Map<String, dynamic>>(
        '/api/tenant/edgeInfos',
        queryParameters: params,
        cancelToken: cancelToken,
      );
      return PageData<TbEdgeInfo>.fromJson(
        response.data ?? const <String, dynamic>{},
        TbEdgeInfo.fromJson,
      );
    } on TbFailure catch (e) {
      if (e.type != TbFailureType.notFound) rethrow;
      final fallback = await _client.get<Map<String, dynamic>>(
        '/api/tenant/edges',
        queryParameters: params,
        cancelToken: cancelToken,
      );
      return PageData<TbEdgeInfo>.fromJson(
        fallback.data ?? const <String, dynamic>{},
        TbEdgeInfo.fromJson,
      );
    }
  }

  @override
  Future<TbEdgeInfo> getTenantEdgeByName(String edgeName) async {
    final queryParams = <String, dynamic>{'edgeName': edgeName};
    try {
      final response = await _client.get<Map<String, dynamic>>(
        '/api/tenant/edge',
        queryParameters: queryParams,
      );
      return TbEdgeInfo.fromJson(response.data ?? const <String, dynamic>{});
    } on TbFailure catch (e) {
      if (e.type != TbFailureType.notFound) rethrow;
      final fallback = await _client.get<Map<String, dynamic>>(
        '/api/tenant/edges',
        queryParameters: queryParams,
      );
      return TbEdgeInfo.fromJson(fallback.data ?? const <String, dynamic>{});
    }
  }

  @override
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
      return PageData<TbDeviceInfo>.fromJson(
        response.data ?? const <String, dynamic>{},
        TbDeviceInfo.fromJson,
      );
    } on TbFailure catch (e) {
      if (e.type != TbFailureType.notFound) rethrow;
      return getTenantDevices(query, type: type, cancelToken: cancelToken);
    }
  }

  @override
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
    return PageData<TbDeviceInfo>.fromJson(
      response.data ?? const <String, dynamic>{},
      TbDeviceInfo.fromJson,
    );
  }

  @override
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

  @override
  Future<TbDeviceInfo> assignDeviceToTenant(
    String tenantId,
    String deviceId,
  ) async {
    final response = await _client.post<Map<String, dynamic>>(
      '/api/tenant/${tenantId.trim()}/device/${deviceId.trim()}',
    );
    return TbDeviceInfo.fromJson(response.data ?? const <String, dynamic>{});
  }

  @override
  Future<PageData<TbAssetInfo>> getTenantAssetInfos(
    PageQuery query, {
    String? type,
    CancelToken? cancelToken,
  }) async {
    final params = <String, dynamic>{
      ...query.toQueryParameters(),
      if (type != null && type.isNotEmpty) 'type': type,
    };
    try {
      final response = await _client.get<Map<String, dynamic>>(
        '/api/tenant/assetInfos',
        queryParameters: params,
        cancelToken: cancelToken,
      );
      return PageData<TbAssetInfo>.fromJson(
        response.data ?? const <String, dynamic>{},
        TbAssetInfo.fromJson,
      );
    } on TbFailure catch (e) {
      if (e.type != TbFailureType.notFound) rethrow;
      return getTenantAssets(query, type: type, cancelToken: cancelToken);
    }
  }

  @override
  Future<PageData<TbAssetInfo>> getTenantAssets(
    PageQuery query, {
    String? type,
    CancelToken? cancelToken,
  }) async {
    final response = await _client.get<Map<String, dynamic>>(
      '/api/tenant/assets',
      queryParameters: <String, dynamic>{
        ...query.toQueryParameters(),
        if (type != null && type.isNotEmpty) 'type': type,
      },
      cancelToken: cancelToken,
    );
    return PageData<TbAssetInfo>.fromJson(
      response.data ?? const <String, dynamic>{},
      TbAssetInfo.fromJson,
    );
  }

  @override
  Future<TbAssetInfo> getTenantAssetByName(String assetName) async {
    final params = <String, dynamic>{'assetName': assetName};
    try {
      final response = await _client.get<Map<String, dynamic>>(
        '/api/tenant/asset',
        queryParameters: params,
      );
      return TbAssetInfo.fromJson(response.data ?? const <String, dynamic>{});
    } on TbFailure catch (e) {
      if (e.type != TbFailureType.notFound) rethrow;
      final fallback = await _client.get<Map<String, dynamic>>(
        '/api/tenant/assets',
        queryParameters: params,
      );
      return TbAssetInfo.fromJson(fallback.data ?? const <String, dynamic>{});
    }
  }

  @override
  Future<TbCustomerInfo> getTenantCustomerByTitle(String customerTitle) async {
    final response = await _client.get<Map<String, dynamic>>(
      '/api/tenant/customers',
      queryParameters: <String, dynamic>{'customerTitle': customerTitle},
    );
    return TbCustomerInfo.fromJson(response.data ?? const <String, dynamic>{});
  }

  @override
  Future<PageData<TbDashboardInfo>> getTenantDashboards(
    PageQuery query, {
    bool? mobile,
    CancelToken? cancelToken,
  }) async {
    final response = await _client.get<Map<String, dynamic>>(
      '/api/tenant/dashboards',
      queryParameters: <String, dynamic>{
        ...query.toQueryParameters(),
        if (mobile != null) 'mobile': mobile,
      },
      cancelToken: cancelToken,
    );
    return PageData<TbDashboardInfo>.fromJson(
      response.data ?? const <String, dynamic>{},
      TbDashboardInfo.fromJson,
    );
  }

  @override
  Future<PageData<TbDashboardInfo>> getTenantDashboardsByTenantId(
    String tenantId,
    PageQuery query, {
    CancelToken? cancelToken,
  }) async {
    final response = await _client.get<Map<String, dynamic>>(
      '/api/tenant/${tenantId.trim()}/dashboards',
      queryParameters: query.toQueryParameters(),
      cancelToken: cancelToken,
    );
    return PageData<TbDashboardInfo>.fromJson(
      response.data ?? const <String, dynamic>{},
      TbDashboardInfo.fromJson,
    );
  }
}

/// Offline Demo implementation of [TenantRepository] for `SessionMode.demo`.
final class DemoTenantRepository implements TenantRepository {
  DemoTenantRepository();

  final List<TbTenantInfo> _tenants = <TbTenantInfo>[
    TbTenantInfo(
      id: 'demo-tenant-1',
      title: 'ThingsBoard DemoCloud Tenant',
      region: 'ap-southeast-1',
      tenantProfileId: 'tp-demo-1',
      tenantProfileName: 'Enterprise IoT',
      country: 'VN',
      state: 'HN',
      city: 'Hanoi',
      address: '1 IoT Boulevard',
      phone: '+84 24 555 0199',
      email: 'tenant@democloud.xyz',
      active: true,
      createdTime: DateTime(2026, 1, 15).millisecondsSinceEpoch,
    ),
    TbTenantInfo(
      id: 'demo-tenant-2',
      title: 'Regional Water Authority',
      region: 'ap-southeast-1',
      tenantProfileId: 'tp-demo-2',
      tenantProfileName: 'Standard',
      country: 'VN',
      city: 'Da Nang',
      email: 'ops@water-demo.io',
      active: true,
      createdTime: DateTime(2026, 3, 10).millisecondsSinceEpoch,
    ),
  ];

  final List<TbTenantProfileInfo> _profiles = <TbTenantProfileInfo>[
    TbTenantProfileInfo(
      id: 'tp-demo-1',
      name: 'Enterprise IoT',
      description: 'Dedicated rule engine & high-throughput telemetry',
      isDefault: true,
      isolatedTbRuleEngine: true,
      createdTime: DateTime(2026, 1, 1).millisecondsSinceEpoch,
    ),
    TbTenantProfileInfo(
      id: 'tp-demo-2',
      name: 'Standard',
      description: 'Shared rule engine for standard fleets',
      isDefault: false,
      createdTime: DateTime(2026, 1, 2).millisecondsSinceEpoch,
    ),
  ];

  final List<TbEntityViewInfo> _entityViews = <TbEntityViewInfo>[
    TbEntityViewInfo(
      id: 'ev-demo-1',
      name: 'Public Flood Telemetry View',
      type: 'FloodTelemetry',
      entityId: const EntityId(entityType: EntityType.device, id: 'dev-1'),
      ownerName: 'Smart City Ops',
      customerIsPublic: true,
      createdTime: DateTime(2026, 6, 1).millisecondsSinceEpoch,
    ),
    TbEntityViewInfo(
      id: 'ev-demo-2',
      name: 'HVAC Partner View',
      type: 'ClimateView',
      entityId: const EntityId(entityType: EntityType.device, id: 'dev-2'),
      ownerName: 'Acme Facilities',
      createdTime: DateTime(2026, 6, 12).millisecondsSinceEpoch,
    ),
  ];

  final List<TbEdgeInfo> _edges = <TbEdgeInfo>[
    TbEdgeInfo(
      id: 'edge-demo-1',
      name: 'Flood Station Edge GW-01',
      type: 'IndustrialEdge',
      label: 'River Basin North',
      routingKey: 'demo-edge-rk-01',
      ownerName: 'ThingsBoard DemoCloud Tenant',
      createdTime: DateTime(2026, 5, 20).millisecondsSinceEpoch,
    ),
    TbEdgeInfo(
      id: 'edge-demo-2',
      name: 'Substation Edge GW-02',
      type: 'EnergyEdge',
      label: 'Grid Zone B',
      routingKey: 'demo-edge-rk-02',
      ownerName: 'Acme Facilities',
      createdTime: DateTime(2026, 7, 4).millisecondsSinceEpoch,
    ),
  ];

  TbHomeDashboardInfo _homeDashboard = const TbHomeDashboardInfo(
    dashboardId: 'dash-1',
    hideDashboardToolbar: true,
  );

  static PageData<T> _paginate<T>(List<T> all, PageQuery query) {
    final start = query.page * query.pageSize;
    if (start >= all.length) {
      return PageData<T>(
        data: const [],
        totalPages: (all.length / query.pageSize).ceil(),
        totalElements: all.length,
        hasNext: false,
      );
    }
    final end = (start + query.pageSize).clamp(0, all.length);
    return PageData<T>(
      data: all.sublist(start, end),
      totalPages: (all.length / query.pageSize).ceil(),
      totalElements: all.length,
      hasNext: end < all.length,
    );
  }

  @override
  Future<TbTenantInfo> getTenantInfo(String tenantId) async {
    return _tenants.firstWhere(
      (t) => t.id == tenantId,
      orElse: () => _tenants.first,
    );
  }

  @override
  Future<TbTenantInfo> getTenantById(String tenantId) =>
      getTenantInfo(tenantId);

  @override
  Future<TbTenantInfo> saveTenant(TbTenantInfo tenant) async {
    if (tenant.id.isEmpty) {
      final created = tenant.copyWith(id: 'demo-tenant-${_tenants.length + 1}');
      _tenants.insert(0, created);
      return created;
    }
    final idx = _tenants.indexWhere((t) => t.id == tenant.id);
    if (idx != -1) {
      _tenants[idx] = tenant;
      return tenant;
    }
    _tenants.insert(0, tenant);
    return tenant;
  }

  @override
  Future<void> deleteTenant(String tenantId) async {
    _tenants.removeWhere((t) => t.id == tenantId);
  }

  @override
  Future<PageData<TbTenantInfo>> getTenantInfos(
    PageQuery query, {
    CancelToken? cancelToken,
  }) async {
    final s = query.textSearch?.trim().toLowerCase() ?? '';
    final filtered = _tenants
        .where(
          (t) =>
              s.isEmpty ||
              t.title.toLowerCase().contains(s) ||
              t.email.toLowerCase().contains(s) ||
              t.city.toLowerCase().contains(s),
        )
        .toList(growable: false);
    return _paginate(filtered, query);
  }

  @override
  Future<PageData<TbTenantInfo>> getTenants(
    PageQuery query, {
    CancelToken? cancelToken,
  }) => getTenantInfos(query, cancelToken: cancelToken);

  @override
  Future<List<TbTenantInfo>> getTenantsByIds(List<String> tenantIds) async {
    return _tenants.where((t) => tenantIds.contains(t.id)).toList();
  }

  @override
  Future<TbTenantProfileInfo?> getDefaultTenantProfileInfo() async {
    return _profiles.where((p) => p.isDefault).firstOrNull ??
        _profiles.firstOrNull;
  }

  @override
  Future<TbTenantProfileInfo> getTenantProfileInfo(
    String tenantProfileId,
  ) async {
    return _profiles.firstWhere(
      (p) => p.id == tenantProfileId,
      orElse: () => _profiles.first,
    );
  }

  @override
  Future<TbTenantProfileInfo> getTenantProfileById(String tenantProfileId) =>
      getTenantProfileInfo(tenantProfileId);

  @override
  Future<PageData<TbTenantProfileInfo>> getTenantProfileInfos(
    PageQuery query, {
    CancelToken? cancelToken,
  }) async {
    final s = query.textSearch?.trim().toLowerCase() ?? '';
    final filtered = _profiles
        .where(
          (p) =>
              s.isEmpty ||
              p.name.toLowerCase().contains(s) ||
              p.description.toLowerCase().contains(s),
        )
        .toList(growable: false);
    return _paginate(filtered, query);
  }

  @override
  Future<PageData<TbTenantProfileInfo>> getTenantProfiles(
    PageQuery query, {
    CancelToken? cancelToken,
  }) => getTenantProfileInfos(query, cancelToken: cancelToken);

  @override
  Future<List<TbTenantProfileInfo>> getTenantProfilesByIds(
    List<String> ids,
  ) async {
    return _profiles.where((p) => ids.contains(p.id)).toList();
  }

  @override
  Future<TbTenantProfileInfo> saveTenantProfile(
    TbTenantProfileInfo profile,
  ) async {
    if (profile.id.isEmpty) {
      final created = profile.copyWith(id: 'tp-demo-${_profiles.length + 1}');
      _profiles.add(created);
      return created;
    }
    final idx = _profiles.indexWhere((p) => p.id == profile.id);
    if (idx != -1) {
      _profiles[idx] = profile;
    }
    return profile;
  }

  @override
  Future<TbTenantProfileInfo> setDefaultTenantProfile(
    String tenantProfileId,
  ) async {
    for (var i = 0; i < _profiles.length; i++) {
      _profiles[i] = _profiles[i].copyWith(
        isDefault: _profiles[i].id == tenantProfileId,
      );
    }
    return getTenantProfileInfo(tenantProfileId);
  }

  @override
  Future<void> deleteTenantProfile(String tenantProfileId) async {
    _profiles.removeWhere((p) => p.id == tenantProfileId);
  }

  @override
  Future<PageData<TbUserProfile>> getTenantUsers(
    String tenantId,
    PageQuery query, {
    CancelToken? cancelToken,
  }) async {
    final users = <TbUserProfile>[
      TbUserProfile(
        id: 'demo-user-1',
        email: 'tenant@democloud.xyz',
        authority: Authority.tenantAdmin,
        firstName: 'Demo',
        lastName: 'Admin',
        tenantId: tenantId,
      ),
    ];
    return _paginate(users, query);
  }

  @override
  Future<TbHomeDashboardInfo?> getTenantHomeDashboardInfo() async =>
      _homeDashboard;

  @override
  Future<void> setTenantHomeDashboardInfo(TbHomeDashboardInfo info) async {
    _homeDashboard = info;
  }

  @override
  Future<TbTenantSubscriptionSummary?> getSubscriptionSummary() async {
    return const TbTenantSubscriptionSummary(
      planName: 'Enterprise Demo',
      state: 'ACTIVE',
      usage: <String, dynamic>{
        'devices': 6,
        'maxDevices': 100,
        'assets': 4,
        'maxAssets': 50,
      },
      whiteLabelingAllowed: true,
    );
  }

  @override
  Future<List<Map<String, dynamic>>> getTenantQueues({
    String serviceType = 'TB_RULE_ENGINE',
  }) async {
    return const <Map<String, dynamic>>[
      <String, dynamic>{'name': 'Main', 'topic': 'tb_rule_engine.main'},
    ];
  }

  @override
  Future<PageData<TbEntityViewInfo>> getTenantEntityViews(
    PageQuery query, {
    String? type,
    CancelToken? cancelToken,
  }) async {
    final s = query.textSearch?.trim().toLowerCase() ?? '';
    final filtered = _entityViews
        .where((v) {
          if (type != null && type.isNotEmpty && v.type != type) return false;
          if (s.isNotEmpty &&
              !v.name.toLowerCase().contains(s) &&
              !v.type.toLowerCase().contains(s)) {
            return false;
          }
          return true;
        })
        .toList(growable: false);
    return _paginate(filtered, query);
  }

  @override
  Future<TbEntityViewInfo> getTenantEntityViewByName(
    String entityViewName,
  ) async {
    return _entityViews.firstWhere(
      (v) => v.name == entityViewName,
      orElse: () => throw const TbFailure(
        type: TbFailureType.notFound,
        message: 'Entity view not found',
      ),
    );
  }

  @override
  Future<PageData<TbEdgeInfo>> getTenantEdges(
    PageQuery query, {
    String? type,
    CancelToken? cancelToken,
  }) async {
    final s = query.textSearch?.trim().toLowerCase() ?? '';
    final filtered = _edges
        .where((e) {
          if (type != null && type.isNotEmpty && e.type != type) return false;
          if (s.isNotEmpty &&
              !e.name.toLowerCase().contains(s) &&
              !e.type.toLowerCase().contains(s) &&
              !e.label.toLowerCase().contains(s)) {
            return false;
          }
          return true;
        })
        .toList(growable: false);
    return _paginate(filtered, query);
  }

  @override
  Future<TbEdgeInfo> getTenantEdgeByName(String edgeName) async {
    return _edges.firstWhere(
      (e) => e.name == edgeName,
      orElse: () => throw const TbFailure(
        type: TbFailureType.notFound,
        message: 'Edge not found',
      ),
    );
  }

  @override
  Future<PageData<TbDeviceInfo>> getTenantDeviceInfos(
    PageQuery query, {
    String? deviceProfileId,
    String? type,
    CancelToken? cancelToken,
  }) async => const PageData<TbDeviceInfo>(
    data: [],
    totalPages: 0,
    totalElements: 0,
    hasNext: false,
  );

  @override
  Future<PageData<TbDeviceInfo>> getTenantDevices(
    PageQuery query, {
    String? type,
    CancelToken? cancelToken,
  }) => getTenantDeviceInfos(query, type: type, cancelToken: cancelToken);

  @override
  Future<TbDeviceInfo> getTenantDeviceByName(String deviceName) async =>
      TbDeviceInfo(id: 'dev-1', name: deviceName, type: 'Default');

  @override
  Future<TbDeviceInfo> assignDeviceToTenant(
    String tenantId,
    String deviceId,
  ) async => TbDeviceInfo(
    id: deviceId,
    name: 'Assigned Device',
    type: 'Default',
    tenantId: tenantId,
  );

  @override
  Future<PageData<TbAssetInfo>> getTenantAssetInfos(
    PageQuery query, {
    String? type,
    CancelToken? cancelToken,
  }) async => const PageData<TbAssetInfo>(
    data: [],
    totalPages: 0,
    totalElements: 0,
    hasNext: false,
  );

  @override
  Future<PageData<TbAssetInfo>> getTenantAssets(
    PageQuery query, {
    String? type,
    CancelToken? cancelToken,
  }) => getTenantAssetInfos(query, type: type, cancelToken: cancelToken);

  @override
  Future<TbAssetInfo> getTenantAssetByName(String assetName) async =>
      TbAssetInfo(id: 'ast-1', name: assetName, type: 'Building');

  @override
  Future<TbCustomerInfo> getTenantCustomerByTitle(String customerTitle) async =>
      TbCustomerInfo(id: 'cust-1', title: customerTitle);

  @override
  Future<PageData<TbDashboardInfo>> getTenantDashboards(
    PageQuery query, {
    bool? mobile,
    CancelToken? cancelToken,
  }) async => const PageData<TbDashboardInfo>(
    data: [],
    totalPages: 0,
    totalElements: 0,
    hasNext: false,
  );

  @override
  Future<PageData<TbDashboardInfo>> getTenantDashboardsByTenantId(
    String tenantId,
    PageQuery query, {
    CancelToken? cancelToken,
  }) => getTenantDashboards(query, cancelToken: cancelToken);
}
