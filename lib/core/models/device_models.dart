import 'package:flutter/foundation.dart';
import 'package:thingsboard_democloud_app/core/models/entity_id.dart';

/// Query filter for `DevicesNotifier`.
@immutable
class TbDeviceQuery {
  const TbDeviceQuery({this.deviceProfileId, this.active, this.textSearch});

  final String? deviceProfileId;
  final bool? active;
  final String? textSearch;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TbDeviceQuery &&
          runtimeType == other.runtimeType &&
          deviceProfileId == other.deviceProfileId &&
          active == other.active &&
          textSearch == other.textSearch;

  @override
  int get hashCode => Object.hash(deviceProfileId, active, textSearch);
}

/// Device profile metadata paired with active/inactive device counts.
@immutable
class TbDeviceProfileSummary {
  const TbDeviceProfileSummary({
    required this.id,
    required this.name,
    this.image,
    this.defaultDashboardId,
    this.transportType = 'DEFAULT',
    this.activeCount = 0,
    this.inactiveCount = 0,
  });

  factory TbDeviceProfileSummary.fromJson(
    Map<String, dynamic> json, {
    int activeCount = 0,
    int inactiveCount = 0,
  }) {
    final idObj = EntityId.maybeFromJson(json['id']);
    final dashObj = EntityId.maybeFromJson(json['defaultDashboardId']);
    return TbDeviceProfileSummary(
      id: idObj?.id ?? (json['id'] as String? ?? ''),
      name: json['name'] as String? ?? '',
      image: json['image'] as String?,
      defaultDashboardId: dashObj?.id,
      transportType: json['transportType'] as String? ?? 'DEFAULT',
      activeCount: activeCount,
      inactiveCount: inactiveCount,
    );
  }

  final String id;
  final String name;
  final String? image;
  final String? defaultDashboardId;
  final String transportType;
  final int activeCount;
  final int inactiveCount;

  TbDeviceProfileSummary copyWith({int? activeCount, int? inactiveCount}) {
    return TbDeviceProfileSummary(
      id: id,
      name: name,
      image: image,
      defaultDashboardId: defaultDashboardId,
      transportType: transportType,
      activeCount: activeCount ?? this.activeCount,
      inactiveCount: inactiveCount ?? this.inactiveCount,
    );
  }
}

/// Device summary/detail model from `/api/deviceInfos/all` and `/api/device/info/{id}`.
@immutable
class TbDeviceInfo {
  const TbDeviceInfo({
    required this.id,
    required this.name,
    required this.type,
    this.label = '',
    this.deviceProfileId,
    this.active = false,
    this.customerId,
    this.ownerName = '',
    this.createdTime = 0,
    this.additionalInfo = const {},
    this.telemetry = const {},
  });

  factory TbDeviceInfo.fromJson(Map<String, dynamic> json) {
    final idObj = EntityId.maybeFromJson(json['id']);
    final profileObj = EntityId.maybeFromJson(json['deviceProfileId']);
    final customerObj = EntityId.maybeFromJson(json['customerId']);
    return TbDeviceInfo(
      id: idObj?.id ?? (json['id'] as String? ?? ''),
      name: json['name'] as String? ?? '',
      type: json['type'] as String? ?? '',
      label: json['label'] as String? ?? '',
      deviceProfileId: profileObj?.id,
      active: json['active'] as bool? ?? false,
      customerId: customerObj?.id,
      ownerName: json['ownerName'] as String? ?? '',
      createdTime: (json['createdTime'] as num?)?.toInt() ?? 0,
      additionalInfo:
          json['additionalInfo'] as Map<String, dynamic>? ?? const {},
    );
  }

  final String id;
  final String name;
  final String type;
  final String label;
  final String? deviceProfileId;
  final bool active;
  final String? customerId;
  final String ownerName;
  final int createdTime;
  final Map<String, dynamic> additionalInfo;
  final Map<String, String> telemetry;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TbDeviceInfo &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          name == other.name &&
          active == other.active;

  @override
  int get hashCode => Object.hash(id, name, active);
}

/// Device transport credentials from `GET /api/device/{deviceId}/credentials`.
@immutable
class TbDeviceCredentials {
  const TbDeviceCredentials({
    required this.id,
    required this.deviceId,
    required this.credentialsType,
    required this.credentialsId,
    this.credentialsValue,
  });

  factory TbDeviceCredentials.fromJson(Map<String, dynamic> json) {
    final idObj = EntityId.maybeFromJson(json['id']);
    final deviceIdObj = EntityId.maybeFromJson(json['deviceId']);
    return TbDeviceCredentials(
      id: idObj?.id ?? '',
      deviceId: deviceIdObj?.id ?? '',
      credentialsType: json['credentialsType'] as String? ?? 'ACCESS_TOKEN',
      credentialsId: json['credentialsId'] as String? ?? '',
      credentialsValue: json['credentialsValue'] as String?,
    );
  }

  final String id;
  final String deviceId;
  final String credentialsType;
  final String credentialsId;
  final String? credentialsValue;
}

/// Result of `POST /api/customer/device/{deviceName}/claim`.
@immutable
class TbClaimResult {
  const TbClaimResult({required this.response, this.device});

  factory TbClaimResult.fromJson(Map<String, dynamic> json) {
    final devMap = json['device'] as Map<String, dynamic>?;
    return TbClaimResult(
      response: json['response'] as String? ?? 'SUCCESS',
      device: devMap != null ? TbDeviceInfo.fromJson(devMap) : null,
    );
  }

  final String response;
  final TbDeviceInfo? device;
}
