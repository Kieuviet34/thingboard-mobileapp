import 'package:flutter/foundation.dart';
import 'package:thingsboard_democloud_app/core/models/entity_id.dart';

/// Query filter for `DevicesNotifier`.
@immutable
class TbDeviceQuery {
  const TbDeviceQuery({
    this.deviceProfileId,
    this.deviceType,
    this.active,
    this.textSearch,
  });

  final String? deviceProfileId;
  final String? deviceType;
  final bool? active;
  final String? textSearch;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TbDeviceQuery &&
          runtimeType == other.runtimeType &&
          deviceProfileId == other.deviceProfileId &&
          deviceType == other.deviceType &&
          active == other.active &&
          textSearch == other.textSearch;

  @override
  int get hashCode =>
      Object.hash(deviceProfileId, deviceType, active, textSearch);
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

/// Device summary/detail model from `/api/deviceInfos/all`, `/api/tenant/deviceInfos`,
/// `/api/customer/{customerId}/deviceInfos`, and `/api/device/info/{id}`.
@immutable
class TbDeviceInfo {
  const TbDeviceInfo({
    required this.id,
    required this.name,
    required this.type,
    this.label = '',
    this.tenantId,
    this.deviceProfileId,
    String deviceProfileName = '',
    this.active = false,
    this.customerId,
    this.ownerName = '',
    this.customerIsPublic = false,
    this.firmwareId,
    this.softwareId,
    this.deviceData = const {},
    this.createdTime = 0,
    this.additionalInfo = const {},
    this.telemetry = const {},
  }) : _deviceProfileName = deviceProfileName;

  static const String nullUuid = '13814000-1dd2-11b2-8080-808080808080';

  factory TbDeviceInfo.fromJson(Map<String, dynamic> json) {
    final idObj = EntityId.maybeFromJson(json['id']);
    final tenantObj = EntityId.maybeFromJson(json['tenantId']);
    final profileObj = EntityId.maybeFromJson(json['deviceProfileId']);
    final customerObj = EntityId.maybeFromJson(json['customerId']);
    final firmwareObj = EntityId.maybeFromJson(json['firmwareId']);
    final softwareObj = EntityId.maybeFromJson(json['softwareId']);
    final rawActive = json['active'];
    final parsedActive = switch (rawActive) {
      bool b => b,
      String s => s.toLowerCase() == 'true',
      _ => false,
    };
    final owner = json['ownerName'] as String?;
    final customerTitle = json['customerTitle'] as String?;
    final rawCustomerId = customerObj?.id;
    final normalizedCustomerId =
        (rawCustomerId == null ||
            rawCustomerId.isEmpty ||
            rawCustomerId == nullUuid)
        ? null
        : rawCustomerId;
    final resolvedType =
        json['type'] as String? ?? json['deviceProfileName'] as String? ?? '';
    final resolvedProfileName =
        json['deviceProfileName'] as String? ?? resolvedType;

    return TbDeviceInfo(
      id: idObj?.id ?? (json['id'] as String? ?? ''),
      name: json['name'] as String? ?? '',
      type: resolvedType,
      label: json['label'] as String? ?? '',
      tenantId: tenantObj?.id,
      deviceProfileId: profileObj?.id,
      deviceProfileName: resolvedProfileName,
      active: parsedActive,
      customerId: normalizedCustomerId,
      ownerName: (owner != null && owner.isNotEmpty)
          ? owner
          : (customerTitle ?? ''),
      customerIsPublic: json['customerIsPublic'] as bool? ?? false,
      firmwareId: firmwareObj?.id,
      softwareId: softwareObj?.id,
      deviceData: json['deviceData'] as Map<String, dynamic>? ?? const {},
      createdTime: (json['createdTime'] as num?)?.toInt() ?? 0,
      additionalInfo:
          json['additionalInfo'] as Map<String, dynamic>? ?? const {},
    );
  }

  final String id;
  final String name;
  final String type;
  final String label;
  final String? tenantId;
  final String? deviceProfileId;
  final String _deviceProfileName;
  final bool active;
  final String? customerId;
  final String ownerName;
  final bool customerIsPublic;
  final String? firmwareId;
  final String? softwareId;
  final Map<String, dynamic> deviceData;
  final int createdTime;
  final Map<String, dynamic> additionalInfo;
  final Map<String, String> telemetry;

  String get deviceProfileName =>
      _deviceProfileName.isNotEmpty ? _deviceProfileName : type;

  TbDeviceInfo copyWith({bool? active}) {
    return TbDeviceInfo(
      id: id,
      name: name,
      type: type,
      label: label,
      tenantId: tenantId,
      deviceProfileId: deviceProfileId,
      deviceProfileName: _deviceProfileName,
      active: active ?? this.active,
      customerId: customerId,
      ownerName: ownerName,
      customerIsPublic: customerIsPublic,
      firmwareId: firmwareId,
      softwareId: softwareId,
      deviceData: deviceData,
      createdTime: createdTime,
      additionalInfo: additionalInfo,
      telemetry: telemetry,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TbDeviceInfo &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          name == other.name &&
          type == other.type &&
          label == other.label &&
          deviceProfileName == other.deviceProfileName &&
          active == other.active &&
          ownerName == other.ownerName &&
          customerId == other.customerId &&
          createdTime == other.createdTime;

  @override
  int get hashCode => Object.hash(
    id,
    name,
    type,
    label,
    deviceProfileName,
    active,
    ownerName,
    customerId,
    createdTime,
  );
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
