import 'package:dio/dio.dart';
import 'package:thingsboard_democloud_app/core/api/client/tb_api_client.dart';
import 'package:thingsboard_democloud_app/core/mock/mock_data.dart';
import 'package:thingsboard_democloud_app/core/models/alarm_models.dart';
import 'package:thingsboard_democloud_app/core/models/entity_id.dart';
import 'package:thingsboard_democloud_app/core/models/pagination.dart';
import 'package:thingsboard_democloud_app/core/models/tb_failure.dart';

/// Alarms v2 listing, ack/clear/assign mutations, assignee lookup, and comments boundary.
abstract interface class AlarmRepository {
  Future<PageData<TbAlarmInfo>> getAlarms(
    PageQuery query,
    TbAlarmFilter filter, {
    CancelToken? cancelToken,
  });

  Future<TbAlarmInfo> getAlarmInfo(String alarmId);
  Future<TbAlarmInfo> ackAlarm(String alarmId);
  Future<TbAlarmInfo> clearAlarm(String alarmId);
  Future<TbAlarmInfo> assignAlarm(String alarmId, String assigneeId);
  Future<TbAlarmInfo> unassignAlarm(String alarmId);

  Future<PageData<TbUserEmailInfo>> getAssignees(
    String alarmId,
    PageQuery query,
  );

  Future<PageData<TbAlarmComment>> getComments(String alarmId, PageQuery query);

  Future<TbAlarmComment> addComment(String alarmId, String text);
}

final class RestAlarmRepository implements AlarmRepository {
  RestAlarmRepository({required TbApiClient client}) : _client = client;

  final TbApiClient _client;

  @override
  Future<PageData<TbAlarmInfo>> getAlarms(
    PageQuery query,
    TbAlarmFilter filter, {
    CancelToken? cancelToken,
  }) async {
    final originator = filter.originatorId;
    final path = originator != null
        ? '/api/v2/alarm/${originator.entityType.wireValue}/${originator.id}'
        : '/api/v2/alarms';

    final params = <String, dynamic>{
      ...query.toQueryParameters(),
      if (filter.textSearch != null && filter.textSearch!.trim().isNotEmpty)
        'textSearch': filter.textSearch!.trim(),
      if (filter.statusList.isNotEmpty)
        'statusList': filter.statusList.map((s) => s.wireValue).toList(),
      if (filter.severityList.isNotEmpty)
        'severityList': filter.severityList.map((s) => s.wireValue).toList(),
      if (filter.typeList.isNotEmpty) 'typeList': filter.typeList.toList(),
      if (filter.assigneeId != null) 'assigneeId': filter.assigneeId,
      if (filter.startTime != null) 'startTime': filter.startTime,
      if (filter.endTime != null) 'endTime': filter.endTime,
    };

    final response = await _client.get<Map<String, dynamic>>(
      path,
      queryParameters: params,
      cancelToken: cancelToken,
    );
    return PageData<TbAlarmInfo>.fromJson(
      response.data ?? const <String, dynamic>{},
      TbAlarmInfo.fromJson,
    );
  }

  @override
  Future<TbAlarmInfo> getAlarmInfo(String alarmId) async {
    final response = await _client.get<Map<String, dynamic>>(
      '/api/alarm/info/$alarmId',
    );
    return TbAlarmInfo.fromJson(response.data ?? const <String, dynamic>{});
  }

  @override
  Future<TbAlarmInfo> ackAlarm(String alarmId) async {
    final response = await _client.post<Map<String, dynamic>>(
      '/api/alarm/$alarmId/ack',
    );
    return TbAlarmInfo.fromJson(response.data ?? const <String, dynamic>{});
  }

  @override
  Future<TbAlarmInfo> clearAlarm(String alarmId) async {
    final response = await _client.post<Map<String, dynamic>>(
      '/api/alarm/$alarmId/clear',
    );
    return TbAlarmInfo.fromJson(response.data ?? const <String, dynamic>{});
  }

  @override
  Future<TbAlarmInfo> assignAlarm(String alarmId, String assigneeId) async {
    final response = await _client.post<Map<String, dynamic>>(
      '/api/alarm/$alarmId/assign/$assigneeId',
    );
    return TbAlarmInfo.fromJson(response.data ?? const <String, dynamic>{});
  }

  @override
  Future<TbAlarmInfo> unassignAlarm(String alarmId) async {
    final response = await _client.delete<Map<String, dynamic>>(
      '/api/alarm/$alarmId/assign',
    );
    return TbAlarmInfo.fromJson(response.data ?? const <String, dynamic>{});
  }

  @override
  Future<PageData<TbUserEmailInfo>> getAssignees(
    String alarmId,
    PageQuery query,
  ) async {
    final response = await _client.get<Map<String, dynamic>>(
      '/api/users/assign/$alarmId',
      queryParameters: query.toQueryParameters(),
    );
    return PageData<TbUserEmailInfo>.fromJson(
      response.data ?? const <String, dynamic>{},
      TbUserEmailInfo.fromJson,
    );
  }

  @override
  Future<PageData<TbAlarmComment>> getComments(
    String alarmId,
    PageQuery query,
  ) async {
    final response = await _client.get<Map<String, dynamic>>(
      '/api/alarm/$alarmId/comment',
      queryParameters: query.toQueryParameters(),
    );
    return PageData<TbAlarmComment>.fromJson(
      response.data ?? const <String, dynamic>{},
      TbAlarmComment.fromJson,
    );
  }

  @override
  Future<TbAlarmComment> addComment(String alarmId, String text) async {
    final response = await _client.post<Map<String, dynamic>>(
      '/api/alarm/$alarmId/comment',
      data: <String, dynamic>{
        'comment': <String, dynamic>{'text': text},
      },
    );
    return TbAlarmComment.fromJson(response.data ?? const <String, dynamic>{});
  }
}

final class DemoAlarmRepository implements AlarmRepository {
  DemoAlarmRepository(List<MockAlarm> seed)
    : _alarms = [
        for (final a in seed)
          TbAlarmInfo(
            id: a.id,
            type: a.type,
            severity: switch (a.severity) {
              AlarmSeverityType.critical => AlarmSeverity.critical,
              AlarmSeverityType.major => AlarmSeverity.major,
              AlarmSeverityType.minor => AlarmSeverity.minor,
              AlarmSeverityType.warning => AlarmSeverity.warning,
              AlarmSeverityType.indeterminate => AlarmSeverity.indeterminate,
            },
            acknowledged: a.isAcknowledged,
            cleared: !a.isActive,
            createdTime: a.createdTime.millisecondsSinceEpoch,
            originator: EntityId(entityType: EntityType.device, id: 'dev-2'),
            originatorName: a.originatorName,
            assigneeName: a.assigneeName,
            dashboardId: a.dashboardId,
          ),
      ],
      _comments = {
        for (final a in seed)
          a.id: [
            for (final c in a.comments)
              TbAlarmComment(
                id: c.id,
                alarmId: a.id,
                type: c.isSystem
                    ? AlarmCommentType.system
                    : AlarmCommentType.other,
                text: c.text,
                firstName: c.authorName,
                createdTime: c.createdTime.millisecondsSinceEpoch,
              ),
          ],
      };

  final List<TbAlarmInfo> _alarms;
  final Map<String, List<TbAlarmComment>> _comments;

  @override
  Future<PageData<TbAlarmInfo>> getAlarms(
    PageQuery query,
    TbAlarmFilter filter, {
    CancelToken? cancelToken,
  }) async {
    final search = (filter.textSearch ?? query.textSearch ?? '')
        .trim()
        .toLowerCase();
    final filtered = _alarms
        .where((a) {
          if (search.isNotEmpty &&
              !a.type.toLowerCase().contains(search) &&
              !a.originatorName.toLowerCase().contains(search)) {
            return false;
          }
          if (filter.severityList.isNotEmpty &&
              !filter.severityList.contains(a.severity)) {
            return false;
          }
          if (filter.statusList.isNotEmpty &&
              !filter.statusList.contains(AlarmSearchStatus.any)) {
            final matchesStatus = filter.statusList.any(
              (s) => switch (s) {
                AlarmSearchStatus.any => true,
                AlarmSearchStatus.active => a.isActive,
                AlarmSearchStatus.cleared => a.cleared,
                AlarmSearchStatus.ack => a.acknowledged,
                AlarmSearchStatus.unack => !a.acknowledged,
              },
            );
            if (!matchesStatus) return false;
          }
          return true;
        })
        .toList(growable: false);

    final start = query.page * query.pageSize;
    if (start >= filtered.length) {
      return PageData<TbAlarmInfo>(
        data: const [],
        totalPages: (filtered.length / query.pageSize).ceil(),
        totalElements: filtered.length,
        hasNext: false,
      );
    }
    final end = (start + query.pageSize).clamp(0, filtered.length);
    return PageData<TbAlarmInfo>(
      data: filtered.sublist(start, end),
      totalPages: (filtered.length / query.pageSize).ceil(),
      totalElements: filtered.length,
      hasNext: end < filtered.length,
    );
  }

  @override
  Future<TbAlarmInfo> getAlarmInfo(String alarmId) async {
    return _alarms.firstWhere(
      (a) => a.id == alarmId,
      orElse: () => throw const TbFailure(
        type: TbFailureType.notFound,
        message: 'Alarm not found',
      ),
    );
  }

  @override
  Future<TbAlarmInfo> ackAlarm(String alarmId) async {
    final idx = _alarms.indexWhere((a) => a.id == alarmId);
    if (idx == -1) {
      throw const TbFailure(
        type: TbFailureType.notFound,
        message: 'Alarm not found',
      );
    }
    final updated = _alarms[idx].copyWith(
      acknowledged: true,
      ackTs: DateTime.now().millisecondsSinceEpoch,
    );
    _alarms[idx] = updated;
    _appendSystemComment(alarmId, 'Alarm was acknowledged by John Doe');
    return updated;
  }

  @override
  Future<TbAlarmInfo> clearAlarm(String alarmId) async {
    final idx = _alarms.indexWhere((a) => a.id == alarmId);
    if (idx == -1) {
      throw const TbFailure(
        type: TbFailureType.notFound,
        message: 'Alarm not found',
      );
    }
    final updated = _alarms[idx].copyWith(
      cleared: true,
      clearTs: DateTime.now().millisecondsSinceEpoch,
    );
    _alarms[idx] = updated;
    _appendSystemComment(alarmId, 'Alarm was cleared by John Doe');
    return updated;
  }

  @override
  Future<TbAlarmInfo> assignAlarm(String alarmId, String assigneeId) async {
    final idx = _alarms.indexWhere((a) => a.id == alarmId);
    if (idx == -1) {
      throw const TbFailure(
        type: TbFailureType.notFound,
        message: 'Alarm not found',
      );
    }
    final candidate = demoAssignees.firstWhere(
      (u) => u.id == assigneeId,
      orElse: () => demoAssignees.first,
    );
    final updated = _alarms[idx].copyWith(
      assigneeId: candidate.id,
      assigneeName: candidate.displayName,
      assigneeEmail: candidate.email,
    );
    _alarms[idx] = updated;
    _appendSystemComment(
      alarmId,
      'Alarm was assigned to ${candidate.displayName}',
    );
    return updated;
  }

  @override
  Future<TbAlarmInfo> unassignAlarm(String alarmId) async {
    final idx = _alarms.indexWhere((a) => a.id == alarmId);
    if (idx == -1) {
      throw const TbFailure(
        type: TbFailureType.notFound,
        message: 'Alarm not found',
      );
    }
    final updated = _alarms[idx].copyWith(clearAssignee: true);
    _alarms[idx] = updated;
    _appendSystemComment(alarmId, 'Alarm was unassigned');
    return updated;
  }

  @override
  Future<PageData<TbUserEmailInfo>> getAssignees(
    String alarmId,
    PageQuery query,
  ) async {
    final search = query.textSearch?.trim().toLowerCase() ?? '';
    final filtered = demoAssignees
        .where(
          (u) =>
              search.isEmpty ||
              u.displayName.toLowerCase().contains(search) ||
              u.email.toLowerCase().contains(search),
        )
        .toList(growable: false);
    return PageData<TbUserEmailInfo>(
      data: filtered,
      totalPages: 1,
      totalElements: filtered.length,
      hasNext: false,
    );
  }

  @override
  Future<PageData<TbAlarmComment>> getComments(
    String alarmId,
    PageQuery query,
  ) async {
    final list = _comments[alarmId] ?? const <TbAlarmComment>[];
    return PageData<TbAlarmComment>(
      data: List<TbAlarmComment>.unmodifiable(list),
      totalPages: 1,
      totalElements: list.length,
      hasNext: false,
    );
  }

  @override
  Future<TbAlarmComment> addComment(String alarmId, String text) async {
    final created = TbAlarmComment(
      id: 'c-${DateTime.now().millisecondsSinceEpoch}',
      alarmId: alarmId,
      userId: 'user-1',
      type: AlarmCommentType.other,
      text: text.trim(),
      firstName: 'John',
      lastName: 'Doe',
      email: 'tenant@thingsboard.org',
      createdTime: DateTime.now().millisecondsSinceEpoch,
    );
    _comments.putIfAbsent(alarmId, () => <TbAlarmComment>[]).add(created);
    return created;
  }

  void _appendSystemComment(String alarmId, String text) {
    _comments
        .putIfAbsent(alarmId, () => <TbAlarmComment>[])
        .add(
          TbAlarmComment(
            id: 'sys-${DateTime.now().microsecondsSinceEpoch}',
            alarmId: alarmId,
            type: AlarmCommentType.system,
            text: text,
            firstName: 'System',
            createdTime: DateTime.now().millisecondsSinceEpoch,
          ),
        );
  }
}
