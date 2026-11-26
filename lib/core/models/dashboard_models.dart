import 'dart:convert';

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
      id: (idObj?.id ?? (json['id'] as String? ?? '')).trim(),
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
    final rawConfig = json['configuration'];
    Map<String, dynamic> configMap = const {};
    if (rawConfig is Map<String, dynamic>) {
      configMap = rawConfig;
    } else if (rawConfig is String && rawConfig.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(rawConfig);
        if (decoded is Map<String, dynamic>) {
          configMap = decoded;
        }
      } catch (_) {
        configMap = const {};
      }
    }

    return TbDashboard(
      info: TbDashboardInfo.fromJson(json, isStarred: isStarred),
      configuration: configMap,
    );
  }

  final TbDashboardInfo info;
  final Map<String, dynamic> configuration;

  static bool _isValidId(String? value) {
    if (value == null) return false;
    final trimmed = value.trim();
    return trimmed.isNotEmpty && trimmed != 'null';
  }

  Iterable<EntityId> _extractStaticEntitiesFromAlias(
    Map<String, dynamic> rawAlias,
  ) sync* {
    final filter = rawAlias['filter'];
    if (filter is! Map<String, dynamic>) return;

    final single = EntityId.maybeFromJson(filter['singleEntity']);
    if (single != null && _isValidId(single.id)) {
      yield single;
    }

    final entityType = EntityType.fromWire(filter['entityType'] as String?);
    final list = filter['entityList'];
    if (list is List) {
      for (final item in list) {
        if (item is String && _isValidId(item)) {
          yield EntityId(
            entityType: entityType == EntityType.unknown
                ? EntityType.device
                : entityType,
            id: item.trim(),
          );
        }
      }
    }
  }

  Iterable<Map<String, dynamic>> _orderedWidgets() sync* {
    final widgets = configuration['widgets'];
    if (widgets is Map<String, dynamic>) {
      final yieldedIds = <String>{};
      final states = configuration['states'];
      if (states is Map<String, dynamic>) {
        final defaultState = states['default'] ?? states.values.firstOrNull;
        if (defaultState is Map<String, dynamic>) {
          final layouts = defaultState['layouts'];
          if (layouts is Map<String, dynamic>) {
            for (final layout in layouts.values) {
              if (layout is! Map<String, dynamic>) continue;
              final layoutWidgets = layout['widgets'];
              if (layoutWidgets is! Map<String, dynamic>) continue;
              for (final widgetId in layoutWidgets.keys) {
                final w = widgets[widgetId];
                if (w is Map<String, dynamic> && yieldedIds.add(widgetId)) {
                  yield w;
                }
              }
            }
          }
        }
      }
      for (final entry in widgets.entries) {
        final w = entry.value;
        if (w is Map<String, dynamic> && yieldedIds.add(entry.key)) {
          yield w;
        }
      }
    } else if (widgets is List) {
      for (final w in widgets) {
        if (w is Map<String, dynamic>) {
          yield w;
        }
      }
    }
  }

  /// Resolves ordered candidate telemetry [EntityId]s, prioritizing aliases
  /// and entity IDs actively referenced by widget datasources so orphaned or
  /// deleted `entityAliases` entries do not shadow active widget devices.
  List<EntityId> resolveCandidateTelemetryEntities() {
    final aliasesRaw = configuration['entityAliases'];
    final aliasById = <String, Map<String, dynamic>>{};
    if (aliasesRaw is Map<String, dynamic>) {
      for (final entry in aliasesRaw.entries) {
        final val = entry.value;
        if (val is Map<String, dynamic>) {
          aliasById[entry.key] = val;
          final innerId = val['id'] as String?;
          if (_isValidId(innerId)) {
            aliasById[innerId!.trim()] = val;
          }
        }
      }
    }

    final widgetCandidates = <EntityId>{};
    for (final rawWidget in _orderedWidgets()) {
      final config = rawWidget['config'];
      if (config is! Map<String, dynamic>) continue;
      final datasources = config['datasources'];
      if (datasources is! List) continue;
      for (final ds in datasources) {
        if (ds is! Map<String, dynamic>) continue;
        final aliasId = ds['entityAliasId'] as String?;
        if (_isValidId(aliasId)) {
          final targetAlias = aliasById[aliasId!.trim()];
          if (targetAlias != null) {
            widgetCandidates.addAll(
              _extractStaticEntitiesFromAlias(targetAlias),
            );
          }
        }
        final deviceId = ds['deviceId'] as String?;
        if (_isValidId(deviceId)) {
          widgetCandidates.add(
            EntityId(entityType: EntityType.device, id: deviceId!.trim()),
          );
        }
        final entityObj = EntityId.maybeFromJson(ds['entityId']);
        if (entityObj != null && _isValidId(entityObj.id)) {
          widgetCandidates.add(entityObj);
        }
      }
    }

    if (widgetCandidates.isNotEmpty) {
      return widgetCandidates.toList(growable: false);
    }

    if (aliasesRaw is Map<String, dynamic>) {
      final aliasCandidates = <EntityId>{};
      for (final rawAlias in aliasesRaw.values) {
        if (rawAlias is Map<String, dynamic>) {
          aliasCandidates.addAll(_extractStaticEntitiesFromAlias(rawAlias));
        }
      }
      if (aliasCandidates.isNotEmpty) {
        return aliasCandidates.toList(growable: false);
      }
    }

    const demoDeviceMap = <String, String>{
      'dash-1': 'dev-1',
      'dash-2': 'dev-4',
      'dash-3': 'dev-5',
      'dash-4': 'dev-6',
      'dash-5': 'dev-3',
      'dash-6': 'dev-4',
    };
    final mappedDeviceId = demoDeviceMap[info.id];
    if (mappedDeviceId != null) {
      return <EntityId>[
        EntityId(entityType: EntityType.device, id: mappedDeviceId),
      ];
    }

    return const <EntityId>[];
  }

  /// Resolves the primary static telemetry [EntityId] synchronously when available.
  EntityId? resolveStaticTelemetryEntity() {
    return resolveCandidateTelemetryEntities().firstOrNull;
  }

  /// Extracts dynamic device-alias filter hints (`deviceType` / `entityName`)
  /// when a live dashboard uses dynamic entity aliases rather than static UUIDs.
  ({String? deviceType, String? nameSearch})?
  extractDynamicDeviceAliasFilter() {
    final aliases = configuration['entityAliases'];
    if (aliases is! Map<String, dynamic>) return null;

    for (final rawAlias in aliases.values) {
      if (rawAlias is! Map<String, dynamic>) continue;
      final filter = rawAlias['filter'];
      if (filter is! Map<String, dynamic>) continue;
      final filterType = filter['type'] as String?;
      if (filterType == 'deviceType') {
        final singular = (filter['deviceType'] as String?)?.trim();
        final pluralList = filter['deviceTypes'];
        final firstPlural = pluralList is List && pluralList.isNotEmpty
            ? (pluralList.first as String?)?.trim()
            : null;
        final resolvedType = (singular != null && singular.isNotEmpty)
            ? singular
            : firstPlural;
        final nameFilter = (filter['deviceNameFilter'] as String?)?.trim();
        return (
          deviceType: (resolvedType != null && resolvedType.isNotEmpty)
              ? resolvedType
              : null,
          nameSearch: (nameFilter != null && nameFilter.isNotEmpty)
              ? nameFilter
              : null,
        );
      }
      if (filterType == 'entityName' || filterType == 'entityType') {
        final entityType = filter['entityType'] as String?;
        if (entityType == null || entityType == 'DEVICE') {
          final nameFilter = (filter['entityNameFilter'] as String?)?.trim();
          return (
            deviceType: null,
            nameSearch: (nameFilter != null && nameFilter.isNotEmpty)
                ? nameFilter
                : null,
          );
        }
      }
    }
    return null;
  }
}

/// Home dashboard assignment returned by `GET /api/dashboard/home/info`
/// and `GET/POST /api/tenant/dashboard/home/info`.
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

  Map<String, dynamic> toJson() => <String, dynamic>{
    'dashboardId': (dashboardId != null && dashboardId!.isNotEmpty)
        ? <String, dynamic>{'entityType': 'DASHBOARD', 'id': dashboardId}
        : null,
    'hideDashboardToolbar': hideDashboardToolbar,
  };
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
    final idObj = EntityId.maybeFromJson(json['id']);
    return TbUserDashboardEntry(
      id: (idObj?.id ?? (json['id'] as String? ?? '')).trim(),
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
