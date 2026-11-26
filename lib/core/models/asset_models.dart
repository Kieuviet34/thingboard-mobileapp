import 'package:flutter/foundation.dart';
import 'package:thingsboard_democloud_app/core/models/entity_id.dart';

/// Query filter for `AssetsNotifier`.
@immutable
class TbAssetQuery {
  const TbAssetQuery({this.assetProfileId, this.textSearch});

  final String? assetProfileId;
  final String? textSearch;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TbAssetQuery &&
          runtimeType == other.runtimeType &&
          assetProfileId == other.assetProfileId &&
          textSearch == other.textSearch;

  @override
  int get hashCode => Object.hash(assetProfileId, textSearch);
}

/// Asset profile summary from `GET /api/assetProfileInfos`.
@immutable
class TbAssetProfileInfo {
  const TbAssetProfileInfo({
    required this.id,
    required this.name,
    this.image,
    this.defaultDashboardId,
  });

  factory TbAssetProfileInfo.fromJson(Map<String, dynamic> json) {
    final idObj = EntityId.maybeFromJson(json['id']);
    final dashObj = EntityId.maybeFromJson(json['defaultDashboardId']);
    return TbAssetProfileInfo(
      id: idObj?.id ?? (json['id'] as String? ?? ''),
      name: json['name'] as String? ?? '',
      image: json['image'] as String?,
      defaultDashboardId: dashObj?.id,
    );
  }

  final String id;
  final String name;
  final String? image;
  final String? defaultDashboardId;
}

/// Asset summary/detail model from `/api/assetInfos/all` and `/api/asset/info/{id}`.
@immutable
class TbAssetInfo {
  const TbAssetInfo({
    required this.id,
    required this.name,
    required this.type,
    this.label = '',
    this.assetProfileId,
    this.customerId,
    this.ownerName = '',
    this.createdTime = 0,
    this.additionalInfo = const {},
  });

  factory TbAssetInfo.fromJson(Map<String, dynamic> json) {
    final idObj = EntityId.maybeFromJson(json['id']);
    final profileObj = EntityId.maybeFromJson(json['assetProfileId']);
    final customerObj = EntityId.maybeFromJson(json['customerId']);
    final owner = json['ownerName'] as String?;
    final customerTitle = json['customerTitle'] as String?;
    return TbAssetInfo(
      id: idObj?.id ?? (json['id'] as String? ?? ''),
      name: json['name'] as String? ?? '',
      type: json['type'] as String? ?? '',
      label: json['label'] as String? ?? '',
      assetProfileId: profileObj?.id,
      customerId: customerObj?.id,
      ownerName: (owner != null && owner.isNotEmpty)
          ? owner
          : (customerTitle ?? ''),
      createdTime: (json['createdTime'] as num?)?.toInt() ?? 0,
      additionalInfo:
          json['additionalInfo'] as Map<String, dynamic>? ?? const {},
    );
  }

  final String id;
  final String name;
  final String type;
  final String label;
  final String? assetProfileId;
  final String? customerId;
  final String ownerName;
  final int createdTime;
  final Map<String, dynamic> additionalInfo;
}

/// Entity relation with resolved source/target names from `/api/relations/info/*`.
@immutable
class TbEntityRelationInfo {
  const TbEntityRelationInfo({
    required this.from,
    required this.to,
    required this.type,
    this.typeGroup = 'COMMON',
    this.fromName = '',
    this.toName = '',
  });

  factory TbEntityRelationInfo.fromJson(Map<String, dynamic> json) {
    return TbEntityRelationInfo(
      from: EntityId.fromJson(
        json['from'] as Map<String, dynamic>? ?? const {},
      ),
      to: EntityId.fromJson(json['to'] as Map<String, dynamic>? ?? const {}),
      type: json['type'] as String? ?? 'Contains',
      typeGroup: json['typeGroup'] as String? ?? 'COMMON',
      fromName: json['fromName'] as String? ?? '',
      toName: json['toName'] as String? ?? '',
    );
  }

  final EntityId from;
  final EntityId to;
  final String type;
  final String typeGroup;
  final String fromName;
  final String toName;
}
