import 'package:flutter/foundation.dart';
import 'package:thingsboard_democloud_app/core/models/alarm_models.dart';
import 'package:thingsboard_democloud_app/core/models/entity_id.dart';

/// User notification inbox item from `GET /api/notifications` and WS `NOTIFICATIONS`.
@immutable
class TbNotification {
  const TbNotification({
    required this.id,
    required this.subject,
    required this.text,
    required this.createdTime,
    this.type = 'GENERAL',
    this.deliveryMethod = 'WEB',
    this.isRead = false,
    this.severity,
    this.info = const {},
  });

  factory TbNotification.fromJson(Map<String, dynamic> json) {
    final idObj = EntityId.maybeFromJson(json['id']);
    final infoMap = json['info'] as Map<String, dynamic>? ?? const {};
    final severityWire = infoMap['alarmSeverity'] as String?;
    final readFlag = json['read'] as bool?;
    final statusStr = json['status'] as String?;
    return TbNotification(
      id: idObj?.id ?? (json['id'] as String? ?? ''),
      subject: json['subject'] as String? ?? '',
      text: json['text'] as String? ?? '',
      createdTime: (json['createdTime'] as num?)?.toInt() ?? 0,
      type: json['type'] as String? ?? 'GENERAL',
      deliveryMethod: json['deliveryMethod'] as String? ?? 'WEB',
      isRead: readFlag ?? (statusStr == 'READ'),
      severity: severityWire != null
          ? AlarmSeverity.fromWire(severityWire)
          : null,
      info: infoMap,
    );
  }

  final String id;
  final String subject;
  final String text;
  final int createdTime;
  final String type;
  final String deliveryMethod;
  final bool isRead;
  final AlarmSeverity? severity;
  final Map<String, dynamic> info;

  TbNotification copyWith({bool? isRead}) {
    return TbNotification(
      id: id,
      subject: subject,
      text: text,
      createdTime: createdTime,
      type: type,
      deliveryMethod: deliveryMethod,
      isRead: isRead ?? this.isRead,
      severity: severity,
      info: info,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TbNotification &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          isRead == other.isRead;

  @override
  int get hashCode => Object.hash(id, isRead);
}

/// User notification delivery preferences from `/api/notification/settings/user`.
@immutable
class TbUserNotificationSettings {
  const TbUserNotificationSettings({this.prefs = const {}});

  factory TbUserNotificationSettings.fromJson(Map<String, dynamic> json) {
    return TbUserNotificationSettings(
      prefs: json['prefs'] as Map<String, dynamic>? ?? const {},
    );
  }

  final Map<String, dynamic> prefs;

  Map<String, dynamic> toJson() => <String, dynamic>{'prefs': prefs};
}
