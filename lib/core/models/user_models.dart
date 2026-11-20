import 'package:flutter/foundation.dart';
import 'package:thingsboard_democloud_app/core/models/entity_id.dart';

/// Authenticated user profile combining `/api/auth/user` and mobile/general settings.
@immutable
class TbUserProfile {
  const TbUserProfile({
    required this.id,
    required this.email,
    required this.authority,
    this.firstName = '',
    this.lastName = '',
    this.phone = '',
    this.tenantId,
    this.customerId,
    this.ownerName = '',
    this.language = 'en_US',
    this.unitSystem = 'METRIC',
    this.homeDashboardId,
    this.homeDashboardTitle,
    this.hideHomeDashboardToolbar = true,
    this.additionalInfo = const {},
  });

  factory TbUserProfile.fromJson(Map<String, dynamic> json) {
    final idObj = EntityId.maybeFromJson(json['id']);
    final tenantObj = EntityId.maybeFromJson(json['tenantId']);
    final customerObj = EntityId.maybeFromJson(json['customerId']);
    final additional =
        json['additionalInfo'] as Map<String, dynamic>? ?? const {};

    return TbUserProfile(
      id: idObj?.id ?? (json['id'] as String? ?? ''),
      email: json['email'] as String? ?? '',
      authority: Authority.fromWire(json['authority'] as String?),
      firstName: json['firstName'] as String? ?? '',
      lastName: json['lastName'] as String? ?? '',
      phone: json['phone'] as String? ?? '',
      tenantId: tenantObj?.id,
      customerId: customerObj?.id,
      ownerName: json['ownerName'] as String? ?? '',
      language: additional['lang'] as String? ?? 'en_US',
      unitSystem: additional['unitSystem'] as String? ?? 'METRIC',
      homeDashboardId: additional['homeDashboardId'] as String?,
      hideHomeDashboardToolbar:
          additional['homeDashboardHideToolbar'] as bool? ?? true,
      additionalInfo: additional,
    );
  }

  final String id;
  final String email;
  final Authority authority;
  final String firstName;
  final String lastName;
  final String phone;
  final String? tenantId;
  final String? customerId;
  final String ownerName;
  final String language;
  final String unitSystem;
  final String? homeDashboardId;
  final String? homeDashboardTitle;
  final bool hideHomeDashboardToolbar;
  final Map<String, dynamic> additionalInfo;

  String get displayName {
    final full = '$firstName $lastName'.trim();
    return full.isEmpty ? email : full;
  }

  String get initials {
    final f = firstName.isNotEmpty ? firstName[0].toUpperCase() : '';
    final l = lastName.isNotEmpty ? lastName[0].toUpperCase() : '';
    final combined = '$f$l';
    if (combined.isNotEmpty) return combined;
    return email.isNotEmpty ? email.substring(0, 1).toUpperCase() : 'U';
  }

  Map<String, dynamic> toUserPayload() {
    return <String, dynamic>{
      if (id.isNotEmpty) 'id': {'entityType': 'USER', 'id': id},
      if (tenantId != null)
        'tenantId': {'entityType': 'TENANT', 'id': tenantId},
      if (customerId != null)
        'customerId': {'entityType': 'CUSTOMER', 'id': customerId},
      'email': email,
      'authority': authority.wireValue,
      'firstName': firstName,
      'lastName': lastName,
      'phone': phone,
      'additionalInfo': <String, dynamic>{
        ...additionalInfo,
        'lang': language,
        'unitSystem': unitSystem,
        if (homeDashboardId != null) 'homeDashboardId': homeDashboardId,
        'homeDashboardHideToolbar': hideHomeDashboardToolbar,
      },
    };
  }

  TbUserProfile copyWith({
    String? firstName,
    String? lastName,
    String? phone,
    String? language,
    String? unitSystem,
    String? homeDashboardId,
    String? homeDashboardTitle,
    bool? hideHomeDashboardToolbar,
  }) {
    return TbUserProfile(
      id: id,
      email: email,
      authority: authority,
      firstName: firstName ?? this.firstName,
      lastName: lastName ?? this.lastName,
      phone: phone ?? this.phone,
      tenantId: tenantId,
      customerId: customerId,
      ownerName: ownerName,
      language: language ?? this.language,
      unitSystem: unitSystem ?? this.unitSystem,
      homeDashboardId: homeDashboardId ?? this.homeDashboardId,
      homeDashboardTitle: homeDashboardTitle ?? this.homeDashboardTitle,
      hideHomeDashboardToolbar:
          hideHomeDashboardToolbar ?? this.hideHomeDashboardToolbar,
      additionalInfo: additionalInfo,
    );
  }
}
