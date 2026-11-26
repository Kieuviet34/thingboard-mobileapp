import 'package:dio/dio.dart';
import 'package:thingsboard_democloud_app/core/api/client/tb_api_client.dart';
import 'package:thingsboard_democloud_app/core/mock/mock_data.dart';
import 'package:thingsboard_democloud_app/core/models/dashboard_models.dart';
import 'package:thingsboard_democloud_app/core/models/entity_id.dart';
import 'package:thingsboard_democloud_app/core/models/pagination.dart';
import 'package:thingsboard_democloud_app/core/models/tb_failure.dart';

/// Dashboard listing, home dashboard, favorite/visit tracking, and detail boundary.
abstract interface class DashboardRepository {
  Future<PageData<TbDashboardInfo>> getDashboards(
    PageQuery query, {
    Authority? authority,
    String? customerId,
    CancelToken? cancelToken,
  });

  Future<TbHomeDashboardInfo?> getHomeDashboardInfo();
  Future<UserDashboardsInfo> getLastVisitedDashboards();
  Future<UserDashboardsInfo> reportDashboardAction(
    String dashboardId,
    String action,
  );
  Future<TbDashboard> getDashboardById(String dashboardId);
}

final class RestDashboardRepository implements DashboardRepository {
  RestDashboardRepository({required TbApiClient client}) : _client = client;

  static const String _nullUuid = '13814000-1dd2-11b2-8080-808080808080';

  final TbApiClient _client;

  /// Detects either HTTP 404 or Spring MVC `/api/user/{userId}` path collision
  /// on pre-3.6 servers (HTTP 400 `"Invalid UUID string: <segment>"`).
  /// Never matches HTTP 403 (`permissionDenied`) or unrelated 400 errors.
  static bool _isMissingUserDashboardEndpoint(TbFailure e, String segment) {
    if (e.type == TbFailureType.notFound) return true;
    if (e.type == TbFailureType.validation) {
      final msg = e.message.toLowerCase();
      return msg.contains('invalid uuid string') &&
          msg.contains(segment.toLowerCase());
    }
    return false;
  }

  static bool _hasScopedCustomerId(String? customerId) =>
      customerId != null && customerId.isNotEmpty && customerId != _nullUuid;

  @override
  Future<PageData<TbDashboardInfo>> getDashboards(
    PageQuery query, {
    Authority? authority,
    String? customerId,
    CancelToken? cancelToken,
  }) async {
    final mobileParams = <String, dynamic>{
      ...query.toQueryParameters(),
      'mobile': true,
    };

    try {
      final response = await _client.get<Map<String, dynamic>>(
        '/api/user/dashboards',
        queryParameters: mobileParams,
        cancelToken: cancelToken,
      );
      return PageData<TbDashboardInfo>.fromJson(
        response.data ?? const <String, dynamic>{},
        TbDashboardInfo.fromJson,
      );
    } on TbFailure catch (e) {
      if (!_isMissingUserDashboardEndpoint(e, 'dashboards')) rethrow;

      if (authority == Authority.customerUser &&
          _hasScopedCustomerId(customerId)) {
        final customerResp = await _client.get<Map<String, dynamic>>(
          '/api/customer/$customerId/dashboards',
          queryParameters: <String, dynamic>{
            ...query.toQueryParameters(),
            'includeCustomers': true,
          },
          cancelToken: cancelToken,
        );
        return PageData<TbDashboardInfo>.fromJson(
          customerResp.data ?? const <String, dynamic>{},
          TbDashboardInfo.fromJson,
        );
      }

      try {
        final tenantResp = await _client.get<Map<String, dynamic>>(
          '/api/tenant/dashboards',
          queryParameters: mobileParams,
          cancelToken: cancelToken,
        );
        return PageData<TbDashboardInfo>.fromJson(
          tenantResp.data ?? const <String, dynamic>{},
          TbDashboardInfo.fromJson,
        );
      } on TbFailure catch (tenantErr) {
        if (tenantErr.type != TbFailureType.notFound) rethrow;
        final allResp = await _client.get<Map<String, dynamic>>(
          '/api/dashboards/all',
          queryParameters: <String, dynamic>{
            ...query.toQueryParameters(),
            'includeCustomers': true,
          },
          cancelToken: cancelToken,
        );
        return PageData<TbDashboardInfo>.fromJson(
          allResp.data ?? const <String, dynamic>{},
          TbDashboardInfo.fromJson,
        );
      }
    }
  }

  @override
  Future<TbHomeDashboardInfo?> getHomeDashboardInfo() async {
    try {
      final response = await _client.get<Map<String, dynamic>>(
        '/api/dashboard/home/info',
      );
      final data = response.data;
      return data != null ? TbHomeDashboardInfo.fromJson(data) : null;
    } on TbFailure catch (e) {
      if (e.type == TbFailureType.notFound) return null;
      rethrow;
    }
  }

  @override
  Future<UserDashboardsInfo> getLastVisitedDashboards() async {
    try {
      final response = await _client.get<Map<String, dynamic>>(
        '/api/user/lastVisitedDashboards',
      );
      return UserDashboardsInfo.fromJson(
        response.data ?? const <String, dynamic>{},
      );
    } on TbFailure catch (e) {
      if (_isMissingUserDashboardEndpoint(e, 'lastVisitedDashboards')) {
        return const UserDashboardsInfo();
      }
      rethrow;
    }
  }

  @override
  Future<UserDashboardsInfo> reportDashboardAction(
    String dashboardId,
    String action,
  ) async {
    try {
      final response = await _client.get<Map<String, dynamic>>(
        '/api/user/dashboards/${dashboardId.trim()}/$action',
      );
      return UserDashboardsInfo.fromJson(
        response.data ?? const <String, dynamic>{},
      );
    } on TbFailure catch (e) {
      if (_isMissingUserDashboardEndpoint(e, 'dashboards')) {
        return const UserDashboardsInfo();
      }
      rethrow;
    }
  }

  @override
  Future<TbDashboard> getDashboardById(String dashboardId) async {
    final cleanId = dashboardId.trim();
    final response = await _client.get<Map<String, dynamic>>(
      '/api/dashboard/$cleanId',
      queryParameters: const <String, dynamic>{'includeResources': true},
    );
    return TbDashboard.fromJson(response.data ?? const <String, dynamic>{});
  }
}

final class DemoDashboardRepository implements DashboardRepository {
  DemoDashboardRepository(List<MockDashboard> seed)
    : _items = [
        for (var i = 0; i < seed.length; i++)
          TbDashboardInfo(
            id: seed[i].id,
            title: seed[i].title,
            description: seed[i].description,
            metrics: seed[i].metrics,
            isStarred: i == 0,
            createdTime: DateTime(2026, 11, 10 + i).millisecondsSinceEpoch,
          ),
      ];

  final List<TbDashboardInfo> _items;
  final List<String> _recentIds = ['dash-1', 'dash-2'];

  @override
  Future<PageData<TbDashboardInfo>> getDashboards(
    PageQuery query, {
    Authority? authority,
    String? customerId,
    CancelToken? cancelToken,
  }) async {
    final search = query.textSearch?.trim().toLowerCase() ?? '';
    final filtered = _items
        .where((d) {
          if (search.isEmpty) return true;
          return d.title.toLowerCase().contains(search) ||
              (d.description?.toLowerCase().contains(search) ?? false);
        })
        .toList(growable: false);

    final start = query.page * query.pageSize;
    if (start >= filtered.length) {
      return PageData<TbDashboardInfo>(
        data: const [],
        totalPages: (filtered.length / query.pageSize).ceil(),
        totalElements: filtered.length,
        hasNext: false,
      );
    }
    final end = (start + query.pageSize).clamp(0, filtered.length);
    return PageData<TbDashboardInfo>(
      data: filtered.sublist(start, end),
      totalPages: (filtered.length / query.pageSize).ceil(),
      totalElements: filtered.length,
      hasNext: end < filtered.length,
    );
  }

  @override
  Future<TbHomeDashboardInfo?> getHomeDashboardInfo() async {
    return const TbHomeDashboardInfo(
      dashboardId: 'dash-1',
      hideDashboardToolbar: true,
    );
  }

  @override
  Future<UserDashboardsInfo> getLastVisitedDashboards() async {
    final starred = _items
        .where((d) => d.isStarred)
        .map(
          (d) => TbUserDashboardEntry(
            id: d.id,
            title: d.title,
            starred: true,
            timestamp: d.createdTime,
          ),
        )
        .toList(growable: false);
    final last = _recentIds
        .map((id) => _items.where((d) => d.id == id).firstOrNull)
        .whereType<TbDashboardInfo>()
        .map(
          (d) => TbUserDashboardEntry(
            id: d.id,
            title: d.title,
            starred: d.isStarred,
            timestamp: d.createdTime,
          ),
        )
        .toList(growable: false);
    return UserDashboardsInfo(last: last, starred: starred);
  }

  @override
  Future<UserDashboardsInfo> reportDashboardAction(
    String dashboardId,
    String action,
  ) async {
    final idx = _items.indexWhere((d) => d.id == dashboardId);
    if (idx != -1) {
      if (action == 'STAR') {
        _items[idx] = _items[idx].copyWith(isStarred: true);
      } else if (action == 'UNSTAR') {
        _items[idx] = _items[idx].copyWith(isStarred: false);
      } else if (action == 'VISIT') {
        _recentIds.remove(dashboardId);
        _recentIds.insert(0, dashboardId);
      }
    }
    return getLastVisitedDashboards();
  }

  @override
  Future<TbDashboard> getDashboardById(String dashboardId) async {
    final info = _items.firstWhere(
      (d) => d.id == dashboardId,
      orElse: () => throw const TbFailure(
        type: TbFailureType.notFound,
        message: 'Dashboard not found',
      ),
    );
    return TbDashboard(info: info);
  }
}
