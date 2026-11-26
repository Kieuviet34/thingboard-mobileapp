import 'package:dio/dio.dart';
import 'package:thingsboard_democloud_app/core/api/client/tb_api_client.dart';
import 'package:thingsboard_democloud_app/core/mock/mock_data.dart';
import 'package:thingsboard_democloud_app/core/models/asset_models.dart';
import 'package:thingsboard_democloud_app/core/models/entity_id.dart';
import 'package:thingsboard_democloud_app/core/models/pagination.dart';
import 'package:thingsboard_democloud_app/core/models/tb_failure.dart';

/// Asset listing, profiles, details, and entity relations boundary.
abstract interface class AssetRepository {
  Future<PageData<TbAssetInfo>> getAssets(
    PageQuery query,
    TbAssetQuery filter, {
    CancelToken? cancelToken,
  });

  Future<TbAssetInfo> getAssetInfo(String assetId);
  Future<PageData<TbAssetProfileInfo>> getAssetProfiles(PageQuery query);
  Future<List<TbEntityRelationInfo>> getRelations(
    EntityId entity, {
    bool outgoing = true,
  });
}

final class RestAssetRepository implements AssetRepository {
  RestAssetRepository({
    required TbApiClient client,
    ({Authority? authority, String? customerId}) Function()? userScopeProvider,
  }) : _client = client,
       _userScopeProvider = userScopeProvider;

  static const String _nullUuid = '13814000-1dd2-11b2-8080-808080808080';

  final TbApiClient _client;
  final ({Authority? authority, String? customerId}) Function()?
  _userScopeProvider;

  @override
  Future<PageData<TbAssetInfo>> getAssets(
    PageQuery query,
    TbAssetQuery filter, {
    CancelToken? cancelToken,
  }) async {
    final search = (filter.textSearch ?? query.textSearch ?? '').trim();
    final peParams = <String, dynamic>{
      ...query.toQueryParameters(),
      'includeCustomers': true,
      if (filter.assetProfileId != null && filter.assetProfileId!.isNotEmpty)
        'assetProfileId': filter.assetProfileId,
      if (search.isNotEmpty) 'textSearch': search,
    };
    try {
      final response = await _client.get<Map<String, dynamic>>(
        '/api/assetInfos/all',
        queryParameters: peParams,
        cancelToken: cancelToken,
      );
      return PageData<TbAssetInfo>.fromJson(
        response.data ?? const <String, dynamic>{},
        TbAssetInfo.fromJson,
      );
    } on TbFailure catch (e) {
      if (e.type != TbFailureType.notFound) rethrow;
      final scope = _userScopeProvider?.call();
      final customerId = scope?.customerId;
      final useCustomerPath =
          scope?.authority == Authority.customerUser &&
          customerId != null &&
          customerId.isNotEmpty &&
          customerId != _nullUuid;
      final fallbackPath = useCustomerPath
          ? '/api/customer/$customerId/assetInfos'
          : '/api/tenant/assetInfos';

      final fallbackParams = <String, dynamic>{
        ...query.toQueryParameters(),
        if (search.isNotEmpty) 'textSearch': search,
      };
      final fallback = await _client.get<Map<String, dynamic>>(
        fallbackPath,
        queryParameters: fallbackParams,
        cancelToken: cancelToken,
      );
      return PageData<TbAssetInfo>.fromJson(
        fallback.data ?? const <String, dynamic>{},
        TbAssetInfo.fromJson,
      );
    }
  }

  /// Direct `GET /api/tenant/assetInfos` (falls back to `GET /api/tenant/assets` on PE 4.4 404).
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

  /// Direct `GET /api/tenant/assets`.
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

  /// Direct `GET /api/tenant/asset?assetName=...` (PE 4.4) with fallback to
  /// `GET /api/tenant/assets?assetName=...` (TB 3.3).
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
  Future<TbAssetInfo> getAssetInfo(String assetId) async {
    final response = await _client.get<Map<String, dynamic>>(
      '/api/asset/info/$assetId',
    );
    return TbAssetInfo.fromJson(response.data ?? const <String, dynamic>{});
  }

  @override
  Future<PageData<TbAssetProfileInfo>> getAssetProfiles(PageQuery query) async {
    final response = await _client.get<Map<String, dynamic>>(
      '/api/assetProfileInfos',
      queryParameters: query.toQueryParameters(),
    );
    return PageData<TbAssetProfileInfo>.fromJson(
      response.data ?? const <String, dynamic>{},
      TbAssetProfileInfo.fromJson,
    );
  }

  @override
  Future<List<TbEntityRelationInfo>> getRelations(
    EntityId entity, {
    bool outgoing = true,
  }) async {
    final dir = outgoing ? 'from' : 'to';
    try {
      final response = await _client.get<List<dynamic>>(
        '/api/relations/info/$dir/${entity.entityType.wireValue}/${entity.id}',
      );
      final list = response.data ?? const [];
      return list
          .whereType<Map<String, dynamic>>()
          .map(TbEntityRelationInfo.fromJson)
          .toList(growable: false);
    } on TbFailure catch (e) {
      if (e.type != TbFailureType.notFound) rethrow;
      final fallback = await _client.get<List<dynamic>>(
        '/api/relations/info',
        queryParameters: outgoing
            ? <String, dynamic>{
                'fromId': entity.id,
                'fromType': entity.entityType.wireValue,
              }
            : <String, dynamic>{
                'toId': entity.id,
                'toType': entity.entityType.wireValue,
              },
      );
      final list = fallback.data ?? const [];
      return list
          .whereType<Map<String, dynamic>>()
          .map(TbEntityRelationInfo.fromJson)
          .toList(growable: false);
    }
  }
}

final class DemoAssetRepository implements AssetRepository {
  DemoAssetRepository(List<MockAsset> assets)
    : _assets = [
        for (final a in assets)
          TbAssetInfo(
            id: a.id,
            name: a.name,
            type: a.type,
            label: a.label,
            ownerName: a.customerName,
            createdTime: a.createdTime.millisecondsSinceEpoch,
          ),
      ];

  final List<TbAssetInfo> _assets;

  @override
  Future<PageData<TbAssetInfo>> getAssets(
    PageQuery query,
    TbAssetQuery filter, {
    CancelToken? cancelToken,
  }) async {
    final search = (filter.textSearch ?? query.textSearch ?? '')
        .trim()
        .toLowerCase();
    final filtered = _assets
        .where(
          (a) =>
              search.isEmpty ||
              a.name.toLowerCase().contains(search) ||
              a.type.toLowerCase().contains(search) ||
              a.label.toLowerCase().contains(search),
        )
        .toList(growable: false);

    final start = query.page * query.pageSize;
    if (start >= filtered.length) {
      return PageData<TbAssetInfo>(
        data: const [],
        totalPages: (filtered.length / query.pageSize).ceil(),
        totalElements: filtered.length,
        hasNext: false,
      );
    }
    final end = (start + query.pageSize).clamp(0, filtered.length);
    return PageData<TbAssetInfo>(
      data: filtered.sublist(start, end),
      totalPages: (filtered.length / query.pageSize).ceil(),
      totalElements: filtered.length,
      hasNext: end < filtered.length,
    );
  }

  @override
  Future<TbAssetInfo> getAssetInfo(String assetId) async {
    return _assets.firstWhere(
      (a) => a.id == assetId,
      orElse: () => throw const TbFailure(
        type: TbFailureType.notFound,
        message: 'Asset not found',
      ),
    );
  }

  @override
  Future<PageData<TbAssetProfileInfo>> getAssetProfiles(PageQuery query) async {
    final types = _assets.map((a) => a.type).toSet().toList(growable: false);
    final profiles = [
      for (var i = 0; i < types.length; i++)
        TbAssetProfileInfo(id: 'ap-${i + 1}', name: types[i]),
    ];
    return PageData<TbAssetProfileInfo>(
      data: profiles,
      totalPages: 1,
      totalElements: profiles.length,
      hasNext: false,
    );
  }

  @override
  Future<List<TbEntityRelationInfo>> getRelations(
    EntityId entity, {
    bool outgoing = true,
  }) async {
    return demoEntityRelations
        .where((r) => outgoing ? r.from == entity : r.to == entity)
        .toList(growable: false);
  }
}
