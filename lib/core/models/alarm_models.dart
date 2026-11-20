import 'package:flutter/foundation.dart';
import 'package:thingsboard_democloud_app/core/models/entity_id.dart';

/// ThingsBoard alarm severity levels ordered highest to lowest.
enum AlarmSeverity {
  critical('CRITICAL', 'Critical'),
  major('MAJOR', 'Major'),
  minor('MINOR', 'Minor'),
  warning('WARNING', 'Warning'),
  indeterminate('INDETERMINATE', 'Indeterminate');

  const AlarmSeverity(this.wireValue, this.label);

  final String wireValue;
  final String label;

  static AlarmSeverity fromWire(String? value) {
    for (final s in AlarmSeverity.values) {
      if (s.wireValue == value) return s;
    }
    return AlarmSeverity.indeterminate;
  }
}

/// Alarm search status filters accepted by `GET /api/v2/alarms` and `AlarmDataQuery`.
enum AlarmSearchStatus {
  any('ANY', 'Any'),
  active('ACTIVE', 'Active'),
  cleared('CLEARED', 'Cleared'),
  ack('ACK', 'Acknowledged'),
  unack('UNACK', 'Unacknowledged');

  const AlarmSearchStatus(this.wireValue, this.label);

  final String wireValue;
  final String label;
}

/// Alarm comment types (`SYSTEM` vs user-authored `OTHER`).
enum AlarmCommentType {
  system('SYSTEM'),
  other('OTHER');

  const AlarmCommentType(this.wireValue);

  final String wireValue;

  static AlarmCommentType fromWire(String? value) =>
      value == 'SYSTEM' ? AlarmCommentType.system : AlarmCommentType.other;
}

/// Filter parameters for querying alarms.
@immutable
class TbAlarmFilter {
  const TbAlarmFilter({
    this.textSearch,
    this.statusList = const {},
    this.severityList = const {},
    this.typeList = const {},
    this.assigneeId,
    this.startTime,
    this.endTime,
    this.originatorId,
  });

  final String? textSearch;
  final Set<AlarmSearchStatus> statusList;
  final Set<AlarmSeverity> severityList;
  final Set<String> typeList;
  final String? assigneeId;
  final int? startTime;
  final int? endTime;
  final EntityId? originatorId;

  TbAlarmFilter copyWith({
    String? textSearch,
    bool clearTextSearch = false,
    Set<AlarmSearchStatus>? statusList,
    Set<AlarmSeverity>? severityList,
    Set<String>? typeList,
    String? assigneeId,
    bool clearAssigneeId = false,
    int? startTime,
    int? endTime,
    EntityId? originatorId,
  }) {
    return TbAlarmFilter(
      textSearch: clearTextSearch ? null : (textSearch ?? this.textSearch),
      statusList: statusList ?? this.statusList,
      severityList: severityList ?? this.severityList,
      typeList: typeList ?? this.typeList,
      assigneeId: clearAssigneeId ? null : (assigneeId ?? this.assigneeId),
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      originatorId: originatorId ?? this.originatorId,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TbAlarmFilter &&
          runtimeType == other.runtimeType &&
          textSearch == other.textSearch &&
          setEquals(statusList, other.statusList) &&
          setEquals(severityList, other.severityList) &&
          setEquals(typeList, other.typeList) &&
          assigneeId == other.assigneeId &&
          startTime == other.startTime &&
          endTime == other.endTime &&
          originatorId == other.originatorId;

  @override
  int get hashCode => Object.hash(
    textSearch,
    Object.hashAllUnordered(statusList),
    Object.hashAllUnordered(severityList),
    Object.hashAllUnordered(typeList),
    assigneeId,
    startTime,
    endTime,
    originatorId,
  );
}

/// Alarm summary/detail model from `/api/v2/alarms` and `/api/alarm/info/{id}`.
@immutable
class TbAlarmInfo {
  const TbAlarmInfo({
    required this.id,
    required this.type,
    required this.severity,
    required this.acknowledged,
    required this.cleared,
    required this.createdTime,
    this.originator,
    this.originatorName = '',
    this.originatorDisplayName,
    this.status,
    this.assigneeId,
    this.assigneeName,
    this.assigneeEmail,
    this.startTs = 0,
    this.endTs = 0,
    this.ackTs = 0,
    this.clearTs = 0,
    this.details = const {},
    this.dashboardId,
  });

  factory TbAlarmInfo.fromJson(Map<String, dynamic> json) {
    final idObj = EntityId.maybeFromJson(json['id']);
    final assignee = json['assignee'] as Map<String, dynamic>?;
    final assigneeIdObj = EntityId.maybeFromJson(json['assigneeId']);
    final first = assignee?['firstName'] as String? ?? '';
    final last = assignee?['lastName'] as String? ?? '';
    final email = assignee?['email'] as String?;
    final fullName = '$first $last'.trim();

    return TbAlarmInfo(
      id: idObj?.id ?? (json['id'] as String? ?? ''),
      type: json['type'] as String? ?? '',
      severity: AlarmSeverity.fromWire(json['severity'] as String?),
      acknowledged: json['acknowledged'] as bool? ?? false,
      cleared: json['cleared'] as bool? ?? false,
      createdTime: (json['createdTime'] as num?)?.toInt() ?? 0,
      originator: EntityId.maybeFromJson(json['originator']),
      originatorName: json['originatorName'] as String? ?? '',
      originatorDisplayName: json['originatorDisplayName'] as String?,
      status: json['status'] as String?,
      assigneeId: assigneeIdObj?.id,
      assigneeName: fullName.isNotEmpty ? fullName : email,
      assigneeEmail: email,
      startTs: (json['startTs'] as num?)?.toInt() ?? 0,
      endTs: (json['endTs'] as num?)?.toInt() ?? 0,
      ackTs: (json['ackTs'] as num?)?.toInt() ?? 0,
      clearTs: (json['clearTs'] as num?)?.toInt() ?? 0,
      details: json['details'] as Map<String, dynamic>? ?? const {},
    );
  }

  final String id;
  final String type;
  final AlarmSeverity severity;
  final bool acknowledged;
  final bool cleared;
  final int createdTime;
  final EntityId? originator;
  final String originatorName;
  final String? originatorDisplayName;
  final String? status;
  final String? assigneeId;
  final String? assigneeName;
  final String? assigneeEmail;
  final int startTs;
  final int endTs;
  final int ackTs;
  final int clearTs;
  final Map<String, dynamic> details;
  final String? dashboardId;

  bool get isActive => !cleared;

  String get displayOriginator =>
      (originatorDisplayName != null && originatorDisplayName!.isNotEmpty)
      ? originatorDisplayName!
      : originatorName;

  String get statusLabel {
    final activePart = isActive ? 'Active' : 'Cleared';
    final ackPart = acknowledged ? 'Acknowledged' : 'Unacknowledged';
    return '$activePart $ackPart';
  }

  TbAlarmInfo copyWith({
    bool? acknowledged,
    bool? cleared,
    String? status,
    String? assigneeId,
    String? assigneeName,
    String? assigneeEmail,
    bool clearAssignee = false,
    int? ackTs,
    int? clearTs,
  }) {
    return TbAlarmInfo(
      id: id,
      type: type,
      severity: severity,
      acknowledged: acknowledged ?? this.acknowledged,
      cleared: cleared ?? this.cleared,
      createdTime: createdTime,
      originator: originator,
      originatorName: originatorName,
      originatorDisplayName: originatorDisplayName,
      status: status ?? this.status,
      assigneeId: clearAssignee ? null : (assigneeId ?? this.assigneeId),
      assigneeName: clearAssignee ? null : (assigneeName ?? this.assigneeName),
      assigneeEmail: clearAssignee
          ? null
          : (assigneeEmail ?? this.assigneeEmail),
      startTs: startTs,
      endTs: endTs,
      ackTs: ackTs ?? this.ackTs,
      clearTs: clearTs ?? this.clearTs,
      details: details,
      dashboardId: dashboardId,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TbAlarmInfo &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          acknowledged == other.acknowledged &&
          cleared == other.cleared &&
          assigneeId == other.assigneeId &&
          assigneeName == other.assigneeName;

  @override
  int get hashCode =>
      Object.hash(id, acknowledged, cleared, assigneeId, assigneeName);
}

/// Alarm comment entry from `/api/alarm/{alarmId}/comment`.
@immutable
class TbAlarmComment {
  const TbAlarmComment({
    required this.id,
    required this.alarmId,
    required this.text,
    required this.createdTime,
    this.userId,
    this.type = AlarmCommentType.other,
    this.firstName,
    this.lastName,
    this.email,
  });

  factory TbAlarmComment.fromJson(Map<String, dynamic> json) {
    final idObj = EntityId.maybeFromJson(json['id']);
    final alarmIdObj = EntityId.maybeFromJson(json['alarmId']);
    final userIdObj = EntityId.maybeFromJson(json['userId']);
    final commentObj = json['comment'];
    final commentText = commentObj is Map<String, dynamic>
        ? (commentObj['text'] as String? ?? '')
        : (commentObj as String? ?? '');

    return TbAlarmComment(
      id: idObj?.id ?? (json['id'] as String? ?? ''),
      alarmId: alarmIdObj?.id ?? '',
      userId: userIdObj?.id,
      type: AlarmCommentType.fromWire(json['type'] as String?),
      text: commentText,
      firstName: json['firstName'] as String?,
      lastName: json['lastName'] as String?,
      email: json['email'] as String?,
      createdTime: (json['createdTime'] as num?)?.toInt() ?? 0,
    );
  }

  final String id;
  final String alarmId;
  final String? userId;
  final AlarmCommentType type;
  final String text;
  final String? firstName;
  final String? lastName;
  final String? email;
  final int createdTime;

  bool get isSystem => type == AlarmCommentType.system;

  String get authorName {
    if (isSystem) return 'System';
    final full = '${firstName ?? ''} ${lastName ?? ''}'.trim();
    return full.isNotEmpty ? full : (email ?? 'User');
  }

  String get initials {
    if (isSystem) return 'SY';
    final f = (firstName != null && firstName!.isNotEmpty)
        ? firstName![0].toUpperCase()
        : '';
    final l = (lastName != null && lastName!.isNotEmpty)
        ? lastName![0].toUpperCase()
        : '';
    final combined = '$f$l';
    if (combined.isNotEmpty) return combined;
    return (email != null && email!.isNotEmpty)
        ? email!.substring(0, 1).toUpperCase()
        : 'U';
  }
}

/// User candidate for alarm assignment from `GET /api/users/assign/{alarmId}`.
@immutable
class TbUserEmailInfo {
  const TbUserEmailInfo({
    required this.id,
    required this.email,
    this.firstName,
    this.lastName,
  });

  factory TbUserEmailInfo.fromJson(Map<String, dynamic> json) {
    final idObj = EntityId.maybeFromJson(json['id']);
    return TbUserEmailInfo(
      id: idObj?.id ?? (json['id'] as String? ?? ''),
      email: json['email'] as String? ?? '',
      firstName: json['firstName'] as String?,
      lastName: json['lastName'] as String?,
    );
  }

  final String id;
  final String email;
  final String? firstName;
  final String? lastName;

  String get displayName {
    final full = '${firstName ?? ''} ${lastName ?? ''}'.trim();
    return full.isNotEmpty ? full : email;
  }
}
