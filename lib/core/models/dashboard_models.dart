import 'package:flutter/foundation.dart';
import 'package:thingsboard_democloud_app/core/models/entity_id.dart';

/// Dashboard summary metadata from `/api/user/dashboards` or `/api/tenant/dashboards`.
@immutable
class TbDashboardInfo {
  const TbDashboardInfo({
    required this.id,
    required this.title,
    this.image,
    this.mobileHide = false,
    this.mobileOrder,
    this.assignedCustomers = const [],
    this.createdTime = 0,
    this.isStarred = false,
    this.metrics = const {},
    this.description,
  });

  factory TbDashboardInfo.fromJson(
    Map<String, dynamic> json, {
    bool isStarred = false,
  }) {
    final idObj = EntityId.maybeFromJson(json['id']);
    final rawCustomers =
        json['assignedCustomers'] as List<dynamic>? ?? const [];
    final customerTitles = rawCustomers
        .whereType<Map<String, dynamic>>()
        .map((c) => c['title'] as String? ?? '')
        .where((t) => t.isNotEmpty)
        .toList(growable: false);

    return TbDashboardInfo(
      id: idObj?.id ?? (json['id'] as String? ?? ''),
      title: json['title'] as String? ?? json['name'] as String? ?? '',
      image: json['image'] as String?,
      mobileHide: json['mobileHide'] as bool? ?? false,
      mobileOrder: (json['mobileOrder'] as num?)?.toInt(),
      assignedCustomers: customerTitles,
      createdTime: (json['createdTime'] as num?)?.toInt() ?? 0,
      isStarred: isStarred,
    );
  }

  final String id;
  final String title;
  final String? image;
  final bool mobileHide;
  final int? mobileOrder;
  final List<String> assignedCustomers;
  final int createdTime;
  final bool isStarred;

  /// Optional quick metrics for Demo/native summary cards.
  final Map<String, String> metrics;
  final String? description;

  TbDashboardInfo copyWith({
    String? title,
    bool? isStarred,
    Map<String, String>? metrics,
  }) {
    return TbDashboardInfo(
      id: id,
      title: title ?? this.title,
      image: image,
      mobileHide: mobileHide,
      mobileOrder: mobileOrder,
      assignedCustomers: assignedCustomers,
      createdTime: createdTime,
      isStarred: isStarred ?? this.isStarred,
      metrics: metrics ?? this.metrics,
      description: description,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TbDashboardInfo &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          title == other.title &&
          isStarred == other.isStarred;

  @override
  int get hashCode => Object.hash(id, title, isStarred);
}

/// Full dashboard definition returned by `GET /api/dashboard/{dashboardId}`.
@immutable
class TbDashboard {
  const TbDashboard({required this.info, this.configuration = const {}});

  factory TbDashboard.fromJson(
    Map<String, dynamic> json, {
    bool isStarred = false,
  }) {
    return TbDashboard(
      info: TbDashboardInfo.fromJson(json, isStarred: isStarred),
      configuration: json['configuration'] as Map<String, dynamic>? ?? const {},
    );
  }

  final TbDashboardInfo info;
  final Map<String, dynamic> configuration;
}

/// Home dashboard assignment returned by `GET /api/dashboard/home/info`.
@immutable
class TbHomeDashboardInfo {
  const TbHomeDashboardInfo({
    this.dashboardId,
    this.hideDashboardToolbar = true,
  });

  factory TbHomeDashboardInfo.fromJson(Map<String, dynamic> json) {
    final idObj = EntityId.maybeFromJson(json['dashboardId']);
    return TbHomeDashboardInfo(
      dashboardId: idObj?.id,
      hideDashboardToolbar: json['hideDashboardToolbar'] as bool? ?? true,
    );
  }

  final String? dashboardId;
  final bool hideDashboardToolbar;
}

/// Last-visited and starred dashboard entry in `UserDashboardsInfo`.
@immutable
class TbUserDashboardEntry {
  const TbUserDashboardEntry({
    required this.id,
    required this.title,
    this.starred = false,
    this.timestamp = 0,
  });

  factory TbUserDashboardEntry.fromJson(
    Map<String, dynamic> json, {
    bool defaultStarred = false,
  }) {
    return TbUserDashboardEntry(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? '',
      starred: json['starred'] as bool? ?? defaultStarred,
      timestamp:
          (json['lastVisited'] as num?)?.toInt() ??
          (json['starredAt'] as num?)?.toInt() ??
          0,
    );
  }

  final String id;
  final String title;
  final bool starred;
  final int timestamp;
}

/// Response from `GET /api/user/lastVisitedDashboards`.
@immutable
class UserDashboardsInfo {
  const UserDashboardsInfo({this.last = const [], this.starred = const []});

  factory UserDashboardsInfo.fromJson(Map<String, dynamic> json) {
    final rawLast = json['last'] as List<dynamic>? ?? const [];
    final rawStarred = json['starred'] as List<dynamic>? ?? const [];
    return UserDashboardsInfo(
      last: rawLast
          .whereType<Map<String, dynamic>>()
          .map(TbUserDashboardEntry.fromJson)
          .toList(growable: false),
      starred: rawStarred
          .whereType<Map<String, dynamic>>()
          .map((e) => TbUserDashboardEntry.fromJson(e, defaultStarred: true))
          .toList(growable: false),
    );
  }

  final List<TbUserDashboardEntry> last;
  final List<TbUserDashboardEntry> starred;
}
