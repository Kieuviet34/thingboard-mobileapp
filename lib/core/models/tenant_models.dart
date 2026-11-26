import 'package:flutter/foundation.dart';
import 'package:thingsboard_democloud_app/core/models/entity_id.dart';

/// Tenant detail & summary model covering ThingsBoard `Tenant` and `TenantInfo`
/// schemas across PE 4.4.x (`thingsboard.cloud`) and TB 3.3.x (`democloud.xyz`).
@immutable
class TbTenantInfo {
  const TbTenantInfo({
    required this.id,
    required this.title,
    this.name = '',
    this.region = '',
    this.tenantProfileId,
    this.tenantProfileName = 'Default',
    this.country = '',
    this.state = '',
    this.city = '',
    this.address = '',
    this.address2 = '',
    this.zip = '',
    this.phone = '',
    this.email = '',
    this.active = true,
    this.createdTime = 0,
    this.additionalInfo = const {},
  });

  factory TbTenantInfo.fromJson(Map<String, dynamic> json) {
    final idObj = EntityId.maybeFromJson(json['id']);
    final profileObj = EntityId.maybeFromJson(json['tenantProfileId']);
    final resolvedTitle =
        json['title'] as String? ?? json['name'] as String? ?? '';
    final rawActive = json['active'];
    final parsedActive = switch (rawActive) {
      bool b => b,
      String s => s.toLowerCase() != 'false',
      _ => true,
    };

    return TbTenantInfo(
      id: idObj?.id ?? (json['id'] as String? ?? ''),
      title: resolvedTitle,
      name: json['name'] as String? ?? resolvedTitle,
      region: json['region'] as String? ?? '',
      tenantProfileId: profileObj?.id,
      tenantProfileName: json['tenantProfileName'] as String? ?? 'Default',
      country: json['country'] as String? ?? '',
      state: json['state'] as String? ?? '',
      city: json['city'] as String? ?? '',
      address: json['address'] as String? ?? '',
      address2: json['address2'] as String? ?? '',
      zip: json['zip'] as String? ?? '',
      phone: json['phone'] as String? ?? '',
      email: json['email'] as String? ?? '',
      active: parsedActive,
      createdTime: (json['createdTime'] as num?)?.toInt() ?? 0,
      additionalInfo:
          json['additionalInfo'] as Map<String, dynamic>? ?? const {},
    );
  }

  final String id;
  final String title;
  final String name;
  final String region;
  final String? tenantProfileId;
  final String tenantProfileName;
  final String country;
  final String state;
  final String city;
  final String address;
  final String address2;
  final String zip;
  final String phone;
  final String email;
  final bool active;
  final int createdTime;
  final Map<String, dynamic> additionalInfo;

  String get locationSummary {
    final parts = [
      city.trim(),
      state.trim(),
      country.trim(),
    ].where((s) => s.isNotEmpty).toList(growable: false);
    return parts.join(', ');
  }

  Map<String, dynamic> toTenantPayload() {
    return <String, dynamic>{
      if (id.isNotEmpty) 'id': {'entityType': 'TENANT', 'id': id},
      'title': title,
      if (region.isNotEmpty) 'region': region,
      if (tenantProfileId != null && tenantProfileId!.isNotEmpty)
        'tenantProfileId': {
          'entityType': 'TENANT_PROFILE',
          'id': tenantProfileId,
        },
      'country': country,
      'state': state,
      'city': city,
      'address': address,
      'address2': address2,
      'zip': zip,
      'phone': phone,
      'email': email,
      if (additionalInfo.isNotEmpty) 'additionalInfo': additionalInfo,
    };
  }

  TbTenantInfo copyWith({
    String? id,
    String? title,
    String? region,
    String? tenantProfileId,
    String? tenantProfileName,
    String? country,
    String? state,
    String? city,
    String? address,
    String? address2,
    String? zip,
    String? phone,
    String? email,
    bool? active,
    Map<String, dynamic>? additionalInfo,
  }) {
    return TbTenantInfo(
      id: id ?? this.id,
      title: title ?? this.title,
      name: title ?? name,
      region: region ?? this.region,
      tenantProfileId: tenantProfileId ?? this.tenantProfileId,
      tenantProfileName: tenantProfileName ?? this.tenantProfileName,
      country: country ?? this.country,
      state: state ?? this.state,
      city: city ?? this.city,
      address: address ?? this.address,
      address2: address2 ?? this.address2,
      zip: zip ?? this.zip,
      phone: phone ?? this.phone,
      email: email ?? this.email,
      active: active ?? this.active,
      createdTime: createdTime,
      additionalInfo: additionalInfo ?? this.additionalInfo,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TbTenantInfo &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          title == other.title &&
          active == other.active;

  @override
  int get hashCode => Object.hash(id, title, active);
}

/// Tenant profile summary & configuration model (`TenantProfile` / `TenantProfileInfo`).
@immutable
class TbTenantProfileInfo {
  const TbTenantProfileInfo({
    required this.id,
    required this.name,
    this.description = '',
    this.isDefault = false,
    this.isolatedTbCore = false,
    this.isolatedTbRuleEngine = false,
    this.createdTime = 0,
    this.profileData = const {},
  });

  factory TbTenantProfileInfo.fromJson(Map<String, dynamic> json) {
    final idObj = EntityId.maybeFromJson(json['id']);
    return TbTenantProfileInfo(
      id: idObj?.id ?? (json['id'] as String? ?? ''),
      name: json['name'] as String? ?? '',
      description: json['description'] as String? ?? '',
      isDefault: json['default'] as bool? ?? false,
      isolatedTbCore: json['isolatedTbCore'] as bool? ?? false,
      isolatedTbRuleEngine: json['isolatedTbRuleEngine'] as bool? ?? false,
      createdTime: (json['createdTime'] as num?)?.toInt() ?? 0,
      profileData: json['profileData'] as Map<String, dynamic>? ?? const {},
    );
  }

  final String id;
  final String name;
  final String description;
  final bool isDefault;
  final bool isolatedTbCore;
  final bool isolatedTbRuleEngine;
  final int createdTime;
  final Map<String, dynamic> profileData;

  Map<String, dynamic> toPayload() {
    return <String, dynamic>{
      if (id.isNotEmpty) 'id': {'entityType': 'TENANT_PROFILE', 'id': id},
      'name': name,
      'description': description,
      'default': isDefault,
      'isolatedTbRuleEngine': isolatedTbRuleEngine,
      if (profileData.isNotEmpty) 'profileData': profileData,
    };
  }

  TbTenantProfileInfo copyWith({
    String? id,
    String? name,
    String? description,
    bool? isDefault,
  }) {
    return TbTenantProfileInfo(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      isDefault: isDefault ?? this.isDefault,
      isolatedTbCore: isolatedTbCore,
      isolatedTbRuleEngine: isolatedTbRuleEngine,
      createdTime: createdTime,
      profileData: profileData,
    );
  }
}

/// Entity View summary/detail model (`/api/tenant/entityViews` & `/api/tenant/entityViewInfos`).
@immutable
class TbEntityViewInfo {
  const TbEntityViewInfo({
    required this.id,
    required this.name,
    required this.type,
    this.entityId,
    this.tenantId,
    this.customerId,
    this.ownerName = '',
    this.customerIsPublic = false,
    this.startTimeMs = 0,
    this.endTimeMs = 0,
    this.keys = const {},
    this.createdTime = 0,
    this.additionalInfo = const {},
  });

  static const String _nullUuid = '13814000-1dd2-11b2-8080-808080808080';

  factory TbEntityViewInfo.fromJson(Map<String, dynamic> json) {
    final idObj = EntityId.maybeFromJson(json['id']);
    final targetObj = EntityId.maybeFromJson(json['entityId']);
    final tenantObj = EntityId.maybeFromJson(json['tenantId']);
    final customerObj = EntityId.maybeFromJson(json['customerId']);
    final rawCust = customerObj?.id;
    final owner = json['ownerName'] as String?;
    final customerTitle = json['customerTitle'] as String?;

    return TbEntityViewInfo(
      id: idObj?.id ?? (json['id'] as String? ?? ''),
      name: json['name'] as String? ?? '',
      type: json['type'] as String? ?? '',
      entityId: targetObj,
      tenantId: tenantObj?.id,
      customerId: (rawCust == null || rawCust.isEmpty || rawCust == _nullUuid)
          ? null
          : rawCust,
      ownerName: (owner != null && owner.isNotEmpty)
          ? owner
          : (customerTitle ?? ''),
      customerIsPublic: json['customerIsPublic'] as bool? ?? false,
      startTimeMs: (json['startTimeMs'] as num?)?.toInt() ?? 0,
      endTimeMs: (json['endTimeMs'] as num?)?.toInt() ?? 0,
      keys: json['keys'] as Map<String, dynamic>? ?? const {},
      createdTime: (json['createdTime'] as num?)?.toInt() ?? 0,
      additionalInfo:
          json['additionalInfo'] as Map<String, dynamic>? ?? const {},
    );
  }

  final String id;
  final String name;
  final String type;
  final EntityId? entityId;
  final String? tenantId;
  final String? customerId;
  final String ownerName;
  final bool customerIsPublic;
  final int startTimeMs;
  final int endTimeMs;
  final Map<String, dynamic> keys;
  final int createdTime;
  final Map<String, dynamic> additionalInfo;
}

/// Edge instance summary/detail model (`/api/tenant/edges` & `/api/tenant/edgeInfos`).
@immutable
class TbEdgeInfo {
  const TbEdgeInfo({
    required this.id,
    required this.name,
    required this.type,
    this.label = '',
    this.routingKey = '',
    this.tenantId,
    this.customerId,
    this.ownerName = '',
    this.customerIsPublic = false,
    this.cloudEndpoint,
    this.edgeLicenseType,
    this.createdTime = 0,
    this.additionalInfo = const {},
  });

  static const String _nullUuid = '13814000-1dd2-11b2-8080-808080808080';

  factory TbEdgeInfo.fromJson(Map<String, dynamic> json) {
    final idObj = EntityId.maybeFromJson(json['id']);
    final tenantObj = EntityId.maybeFromJson(json['tenantId']);
    final customerObj = EntityId.maybeFromJson(json['customerId']);
    final rawCust = customerObj?.id;
    final owner = json['ownerName'] as String?;
    final customerTitle = json['customerTitle'] as String?;

    return TbEdgeInfo(
      id: idObj?.id ?? (json['id'] as String? ?? ''),
      name: json['name'] as String? ?? '',
      type: json['type'] as String? ?? '',
      label: json['label'] as String? ?? '',
      routingKey: json['routingKey'] as String? ?? '',
      tenantId: tenantObj?.id,
      customerId: (rawCust == null || rawCust.isEmpty || rawCust == _nullUuid)
          ? null
          : rawCust,
      ownerName: (owner != null && owner.isNotEmpty)
          ? owner
          : (customerTitle ?? ''),
      customerIsPublic: json['customerIsPublic'] as bool? ?? false,
      cloudEndpoint: json['cloudEndpoint'] as String?,
      edgeLicenseType: json['edgeLicenseType'] as String?,
      createdTime: (json['createdTime'] as num?)?.toInt() ?? 0,
      additionalInfo:
          json['additionalInfo'] as Map<String, dynamic>? ?? const {},
    );
  }

  final String id;
  final String name;
  final String type;
  final String label;
  final String routingKey;
  final String? tenantId;
  final String? customerId;
  final String ownerName;
  final bool customerIsPublic;
  final String? cloudEndpoint;
  final String? edgeLicenseType;
  final int createdTime;
  final Map<String, dynamic> additionalInfo;
}

/// Optional PE Cloud subscription, usage & white-labeling capability summary
/// (`/api/tenant/subscription*` & `/api/tenant/whiteLabelingAllowed`).
@immutable
class TbTenantSubscriptionSummary {
  const TbTenantSubscriptionSummary({
    this.planName,
    this.state,
    this.usage = const {},
    this.mergedProfileConfig = const {},
    this.trendzUsed = false,
    this.whiteLabelingAllowed = false,
  });

  final String? planName;
  final String? state;
  final Map<String, dynamic> usage;
  final Map<String, dynamic> mergedProfileConfig;
  final bool trendzUsed;
  final bool whiteLabelingAllowed;
}
