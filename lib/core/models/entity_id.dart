import 'package:flutter/foundation.dart';

/// ThingsBoard entity type identifiers.
enum EntityType {
  tenant('TENANT'),
  customer('CUSTOMER'),
  user('USER'),
  dashboard('DASHBOARD'),
  asset('ASSET'),
  device('DEVICE'),
  alarm('ALARM'),
  entityGroup('ENTITY_GROUP'),
  entityView('ENTITY_VIEW'),
  deviceProfile('DEVICE_PROFILE'),
  assetProfile('ASSET_PROFILE'),
  edge('EDGE'),
  otaPackage('OTA_PACKAGE'),
  rpc('RPC'),
  notification('NOTIFICATION'),
  apiKey('API_KEY'),
  unknown('UNKNOWN');

  const EntityType(this.wireValue);

  final String wireValue;

  static EntityType fromWire(String? value) {
    if (value == null) return EntityType.unknown;
    for (final item in EntityType.values) {
      if (item.wireValue == value) return item;
    }
    return EntityType.unknown;
  }
}

/// ThingsBoard user/session authority scopes.
enum Authority {
  sysAdmin('SYS_ADMIN'),
  tenantAdmin('TENANT_ADMIN'),
  customerUser('CUSTOMER_USER'),
  billingAdmin('BILLING_ADMIN'),
  billingService('BILLING_SERVICE'),
  refreshToken('REFRESH_TOKEN'),
  preVerificationToken('PRE_VERIFICATION_TOKEN'),
  mfaConfigurationToken('MFA_CONFIGURATION_TOKEN'),
  unknown('UNKNOWN');

  const Authority(this.wireValue);

  final String wireValue;

  static Authority fromWire(String? value) {
    if (value == null) return Authority.unknown;
    for (final item in Authority.values) {
      if (item.wireValue == value) return item;
    }
    return Authority.unknown;
  }

  /// Display-friendly role label.
  String get displayLabel => switch (this) {
    Authority.sysAdmin => 'System Administrator',
    Authority.tenantAdmin => 'Tenant Administrator',
    Authority.customerUser => 'Customer User',
    Authority.billingAdmin => 'Billing Administrator',
    Authority.billingService => 'Billing Service',
    Authority.refreshToken => 'Refresh Token',
    Authority.preVerificationToken => '2FA Verification',
    Authority.mfaConfigurationToken => '2FA Setup',
    Authority.unknown => 'User',
  };
}

/// Typed UUID reference pairing an [EntityType] and entity UUID string.
@immutable
class EntityId {
  const EntityId({required this.entityType, required this.id});

  factory EntityId.fromJson(Map<String, dynamic> json) {
    return EntityId(
      entityType: EntityType.fromWire(json['entityType'] as String?),
      id: json['id'] as String? ?? '',
    );
  }

  static EntityId? maybeFromJson(Object? value) {
    if (value is Map<String, dynamic>) {
      final parsed = EntityId.fromJson(value);
      return parsed.id.isEmpty ? null : parsed;
    }
    return null;
  }

  final EntityType entityType;
  final String id;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'entityType': entityType.wireValue,
    'id': id,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EntityId &&
          runtimeType == other.runtimeType &&
          entityType == other.entityType &&
          id == other.id;

  @override
  int get hashCode => Object.hash(entityType, id);

  @override
  String toString() => 'EntityId(${entityType.wireValue}:$id)';
}
