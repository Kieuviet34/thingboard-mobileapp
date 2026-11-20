import 'package:flutter/foundation.dart';
import 'package:thingsboard_democloud_app/core/models/entity_id.dart';

/// Audit log query scope.
enum AuditLogScope { tenant, entity, user, customer }

/// Query filter for `AuditLogsNotifier`.
@immutable
class TbAuditLogQuery {
  const TbAuditLogQuery({
    this.scope = AuditLogScope.tenant,
    this.targetId,
    this.entityType,
    this.textSearch,
    this.startTime,
    this.endTime,
    this.actionTypes = const [],
  });

  final AuditLogScope scope;
  final String? targetId;
  final EntityType? entityType;
  final String? textSearch;
  final int? startTime;
  final int? endTime;
  final List<String> actionTypes;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TbAuditLogQuery &&
          runtimeType == other.runtimeType &&
          scope == other.scope &&
          targetId == other.targetId &&
          entityType == other.entityType &&
          textSearch == other.textSearch &&
          startTime == other.startTime &&
          endTime == other.endTime &&
          listEquals(actionTypes, other.actionTypes);

  @override
  int get hashCode => Object.hash(
    scope,
    targetId,
    entityType,
    textSearch,
    startTime,
    endTime,
    Object.hashAll(actionTypes),
  );
}

/// Audit log record from `/api/audit/logs*`.
@immutable
class TbAuditLog {
  const TbAuditLog({
    required this.id,
    required this.entityName,
    required this.entityType,
    required this.actionType,
    required this.isSuccess,
    required this.createdTime,
    this.userId,
    this.userName = '',
    this.actionData = const {},
    this.failureDetails,
  });

  factory TbAuditLog.fromJson(Map<String, dynamic> json) {
    final idObj = EntityId.maybeFromJson(json['id']);
    final entityObj = EntityId.maybeFromJson(json['entityId']);
    final userObj = EntityId.maybeFromJson(json['userId']);
    return TbAuditLog(
      id: idObj?.id ?? (json['id'] as String? ?? ''),
      entityName: json['entityName'] as String? ?? '',
      entityType: entityObj?.entityType ?? EntityType.unknown,
      actionType: json['actionType'] as String? ?? '',
      isSuccess: (json['actionStatus'] as String? ?? 'SUCCESS') == 'SUCCESS',
      createdTime: (json['createdTime'] as num?)?.toInt() ?? 0,
      userId: userObj?.id,
      userName: json['userName'] as String? ?? '',
      actionData: json['actionData'] as Map<String, dynamic>? ?? const {},
      failureDetails: json['actionFailureDetails'] as String?,
    );
  }

  final String id;
  final String entityName;
  final EntityType entityType;
  final String actionType;
  final bool isSuccess;
  final int createdTime;
  final String? userId;
  final String userName;
  final Map<String, dynamic> actionData;
  final String? failureDetails;
}
