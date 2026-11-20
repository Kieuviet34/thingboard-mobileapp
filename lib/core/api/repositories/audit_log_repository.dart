import 'package:dio/dio.dart';
import 'package:thingsboard_democloud_app/core/api/client/tb_api_client.dart';
import 'package:thingsboard_democloud_app/core/mock/mock_data.dart';
import 'package:thingsboard_democloud_app/core/models/audit_log_models.dart';
import 'package:thingsboard_democloud_app/core/models/entity_id.dart';
import 'package:thingsboard_democloud_app/core/models/pagination.dart';

/// Tenant, entity, user, and customer audit log query boundary.
abstract interface class AuditLogRepository {
  Future<PageData<TbAuditLog>> getAuditLogs(
    PageQuery query,
    TbAuditLogQuery filter, {
    CancelToken? cancelToken,
  });
}

final class RestAuditLogRepository implements AuditLogRepository {
  RestAuditLogRepository({required TbApiClient client}) : _client = client;

  final TbApiClient _client;

  @override
  Future<PageData<TbAuditLog>> getAuditLogs(
    PageQuery query,
    TbAuditLogQuery filter, {
    CancelToken? cancelToken,
  }) async {
    final path = switch (filter.scope) {
      AuditLogScope.tenant => '/api/audit/logs',
      AuditLogScope.entity =>
        '/api/audit/logs/entity/${(filter.entityType ?? EntityType.device).wireValue}/${filter.targetId ?? ''}',
      AuditLogScope.user => '/api/audit/logs/user/${filter.targetId ?? ''}',
      AuditLogScope.customer =>
        '/api/audit/logs/customer/${filter.targetId ?? ''}',
    };

    final params = <String, dynamic>{
      ...query.toQueryParameters(),
      if (filter.textSearch != null && filter.textSearch!.trim().isNotEmpty)
        'textSearch': filter.textSearch!.trim(),
      if (filter.startTime != null) 'startTime': filter.startTime,
      if (filter.endTime != null) 'endTime': filter.endTime,
      if (filter.actionTypes.isNotEmpty)
        'actionTypes': filter.actionTypes.join(','),
    };

    final response = await _client.get<Map<String, dynamic>>(
      path,
      queryParameters: params,
      cancelToken: cancelToken,
    );
    return PageData<TbAuditLog>.fromJson(
      response.data ?? const <String, dynamic>{},
      TbAuditLog.fromJson,
    );
  }
}

final class DemoAuditLogRepository implements AuditLogRepository {
  DemoAuditLogRepository(List<MockAuditLog> logs)
    : _logs = [
        for (final l in logs)
          TbAuditLog(
            id: l.id,
            entityName: l.entityName,
            entityType: switch (l.entityType.toUpperCase()) {
              'DEVICE' => EntityType.device,
              'ALARM' => EntityType.alarm,
              'DASHBOARD' => EntityType.dashboard,
              'ASSET' => EntityType.asset,
              _ => EntityType.unknown,
            },
            actionType: l.actionType,
            isSuccess: l.isSuccess,
            createdTime: l.createdTime.millisecondsSinceEpoch,
            userName: 'John Doe',
            actionData: l.actionData,
            failureDetails: l.failureDetails,
          ),
      ];

  final List<TbAuditLog> _logs;

  @override
  Future<PageData<TbAuditLog>> getAuditLogs(
    PageQuery query,
    TbAuditLogQuery filter, {
    CancelToken? cancelToken,
  }) async {
    final search = (filter.textSearch ?? query.textSearch ?? '')
        .trim()
        .toLowerCase();
    final filtered = _logs
        .where((l) {
          if (filter.actionTypes.isNotEmpty &&
              !filter.actionTypes.contains(l.actionType)) {
            return false;
          }
          if (search.isNotEmpty &&
              !l.entityName.toLowerCase().contains(search) &&
              !l.actionType.toLowerCase().contains(search)) {
            return false;
          }
          return true;
        })
        .toList(growable: false);

    return PageData<TbAuditLog>(
      data: filtered,
      totalPages: 1,
      totalElements: filtered.length,
      hasNext: false,
    );
  }
}
