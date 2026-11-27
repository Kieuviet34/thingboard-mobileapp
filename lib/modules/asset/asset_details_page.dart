import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:thingsboard_democloud_app/config/routes/router.dart';
import 'package:thingsboard_democloud_app/config/themes/design_tokens.dart';
import 'package:thingsboard_democloud_app/core/api/controllers/alarm_controller.dart';
import 'package:thingsboard_democloud_app/core/api/controllers/asset_controller.dart';
import 'package:thingsboard_democloud_app/core/api/controllers/telemetry_controller.dart';
import 'package:thingsboard_democloud_app/core/models/asset_models.dart';
import 'package:thingsboard_democloud_app/core/models/entity_id.dart';
import 'package:thingsboard_democloud_app/core/models/tb_failure.dart';
import 'package:thingsboard_democloud_app/core/models/telemetry_models.dart';
import 'package:thingsboard_democloud_app/widgets/icons/tb_icons.dart';
import 'package:thingsboard_democloud_app/widgets/tb_app_bar.dart';
import 'package:thingsboard_democloud_app/widgets/tb_empty_state.dart';
import 'package:thingsboard_democloud_app/widgets/tb_list_row.dart';
import 'package:thingsboard_democloud_app/widgets/tb_metric_pill.dart';
import 'package:thingsboard_democloud_app/widgets/tb_motion.dart';
import 'package:thingsboard_democloud_app/widgets/tb_section_card.dart';
import 'package:thingsboard_democloud_app/widgets/tb_shimmer.dart';
import 'package:thingsboard_democloud_app/widgets/tb_status_badge.dart';

/// Asset details screen with 4 M3 tabs: Telemetry, Attributes, Alarms, and Relations.
class AssetDetailsPage extends ConsumerStatefulWidget {
  const AssetDetailsPage({
    super.key,
    required this.assetId,
    this.embedded = false,
  });

  final String assetId;
  final bool embedded;

  @override
  ConsumerState<AssetDetailsPage> createState() => _AssetDetailsPageState();
}

class _AssetDetailsPageState extends ConsumerState<AssetDetailsPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  TbAttributeScope _attributeScope = TbAttributeScope.serverScope;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  EntityId get _entityId =>
      EntityId(entityType: EntityType.asset, id: widget.assetId);

  Widget _bottomSafeState(Widget child) {
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    return LayoutBuilder(
      builder: (context, constraints) {
        final minHeight = constraints.hasBoundedHeight
            ? math.max(0.0, constraints.maxHeight - bottomInset)
            : 0.0;
        return SingleChildScrollView(
          padding: EdgeInsets.only(bottom: bottomInset),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: minHeight),
            child: Center(child: child),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final assetAsync = ref.watch(assetDetailsProvider(widget.assetId));
    final scheme = Theme.of(context).colorScheme;

    final content = assetAsync.when(
      data: (asset) => _buildAssetContent(context, asset),
      loading: () => const _AssetDetailsShimmer(),
      error: (error, _) {
        final failure = error is TbFailure ? error : null;
        final is403 = failure?.type == TbFailureType.permissionDenied;
        return _bottomSafeState(
          TbEmptyState(
            icon: TbIconKind.assetBuilding,
            title: is403 ? 'Access Restricted' : 'Failed to load asset',
            subtitle: is403
                ? 'You do not have permission to view this asset.'
                : (failure?.message ?? error.toString()),
            actionLabel: is403 ? null : 'Retry',
            onAction: is403
                ? null
                : () => ref.invalidate(assetDetailsProvider(widget.assetId)),
            isError: true,
          ),
        );
      },
    );

    if (widget.embedded) {
      return Container(color: scheme.surface, child: content);
    }

    final title = assetAsync.valueOrNull?.name ?? 'Asset Details';
    return Scaffold(
      appBar: TbAppBar(canGoBack: true, title: Text(title)),
      body: SafeArea(bottom: false, child: content),
    );
  }

  Widget _buildAssetContent(BuildContext context, TbAssetInfo asset) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final scrollableTabs =
        MediaQuery.textScalerOf(context).scale(1.0) > 1.2 ||
        MediaQuery.sizeOf(context).width < 360;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: DesignTokens.maxReadableWidth,
        ),
        child: NestedScrollView(
          headerSliverBuilder: (context, innerBoxIsScrolled) => [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  DesignTokens.spacing16,
                  DesignTokens.spacing16,
                  DesignTokens.spacing16,
                  DesignTokens.spacing8,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: scheme.primaryContainer,
                            borderRadius: DesignTokens.borderRadiusMedium,
                          ),
                          child: Center(
                            child: TbIcon(
                              TbIconKind.assetBuilding,
                              size: DesignTokens.iconMedium,
                              color: scheme.onPrimaryContainer,
                            ),
                          ),
                        ),
                        const SizedBox(width: DesignTokens.spacing12),
                        Expanded(
                          child: Text(
                            asset.name,
                            style: textTheme.titleMedium?.copyWith(
                              color: scheme.onSurface,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: DesignTokens.spacing12),
                    TbSectionCard(
                      title: 'Details',
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          TbKvRow(label: 'Type', value: asset.type),
                          if (asset.label.isNotEmpty)
                            TbKvRow(label: 'Label', value: asset.label),
                          if (asset.ownerName.isNotEmpty)
                            TbKvRow(label: 'Owner', value: asset.ownerName),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SliverPersistentHeader(
              pinned: true,
              delegate: _TabBarHeaderDelegate(
                TabBar(
                  controller: _tabController,
                  isScrollable: scrollableTabs,
                  tabAlignment: scrollableTabs
                      ? TabAlignment.startOffset
                      : TabAlignment.fill,
                  labelColor: scheme.primary,
                  unselectedLabelColor: scheme.onSurfaceVariant,
                  indicatorColor: scheme.primary,
                  tabs: const [
                    Tab(text: 'Telemetry'),
                    Tab(text: 'Attributes'),
                    Tab(text: 'Alarms'),
                    Tab(text: 'Relations'),
                  ],
                ),
                color: scheme.surface,
              ),
            ),
          ],
          body: TabBarView(
            controller: _tabController,
            children: [
              _buildTelemetryTab(),
              _buildAttributesTab(),
              _buildAlarmsTab(),
              _buildRelationsTab(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _errorState(String title, VoidCallback onRetry) => TbEmptyState(
    icon: TbIconKind.assetBuilding,
    title: title,
    actionLabel: 'Retry',
    onAction: onRetry,
    isError: true,
  );

  Widget _tabList(
    List<Widget> children, {
    double topPadding = DesignTokens.spacing16,
  }) => ListView(
    padding: EdgeInsets.fromLTRB(
      DesignTokens.spacing16,
      topPadding,
      DesignTokens.spacing16,
      DesignTokens.bottomScrollPadding(context),
    ),
    children: children,
  );

  Widget _buildTelemetryTab() {
    final telemetryAsync = ref.watch(entityLatestTelemetryProvider(_entityId));
    final historyAsync = ref.watch(entityTelemetryHistoryProvider(_entityId));
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(entityLatestTelemetryProvider(_entityId));
        ref.invalidate(entityTelemetryHistoryProvider(_entityId));
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(
          DesignTokens.spacing16,
          DesignTokens.spacing16,
          DesignTokens.spacing16,
          DesignTokens.bottomScrollPadding(context),
        ),
        children: [
          TbSectionCard(
            title: 'Latest',
            child: telemetryAsync.when(
              error: (e, _) => _errorState(
                'Failed to load telemetry',
                () => ref.invalidate(entityLatestTelemetryProvider(_entityId)),
              ),
              loading: () => const TbShimmerList(itemCount: 2),
              data: (latest) {
                if (latest.isEmpty) {
                  return Text(
                    'No telemetry values',
                    style: textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  );
                }
                return Wrap(
                  spacing: DesignTokens.spacing8,
                  runSpacing: DesignTokens.spacing8,
                  children: [
                    for (final entry in latest.entries)
                      TbMetricPill(
                        icon: TbIcons.kindForTelemetryKey(entry.key),
                        label: entry.key,
                        value: entry.value.displayValue,
                      ),
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: DesignTokens.spacing12),
          TbSectionCard(
            title: 'History (24 Hours)',
            child: historyAsync.when(
              error: (e, _) => _errorState(
                'Failed to load history',
                () => ref.invalidate(entityTelemetryHistoryProvider(_entityId)),
              ),
              loading: () => const TbShimmer(height: 96),
              data: (history) {
                if (history.isEmpty) {
                  return Text(
                    'No history points',
                    style: textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  );
                }
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: DesignTokens.spacing12,
                  children: [
                    for (final entry in history.entries)
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        spacing: DesignTokens.spacing8,
                        children: [
                          Text(
                            entry.key,
                            style: textTheme.labelLarge?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                          TbSparklineChart(
                            values: [
                              for (final pt in entry.value)
                                pt.numericValue ?? 0.0,
                            ],
                            height: 64,
                            color: scheme.primary,
                            semanticLabel: '${entry.key} sparkline chart',
                          ),
                        ],
                      ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAttributesTab() {
    final provider = entityAttributesProvider((
      id: _entityId,
      scope: _attributeScope,
    ));
    final attributesAsync = ref.watch(provider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(
            DesignTokens.spacing16,
            DesignTokens.spacing8,
            DesignTokens.spacing16,
            DesignTokens.spacing4,
          ),
          child: Row(
            spacing: DesignTokens.spacing8,
            children: [
              for (final scope in TbAttributeScope.values)
                FilterChip(
                  label: Text(scope.label),
                  selected: _attributeScope == scope,
                  onSelected: (_) => setState(() => _attributeScope = scope),
                ),
            ],
          ),
        ),
        Expanded(
          child: attributesAsync.when(
            error: (e, _) => _bottomSafeState(
              _errorState(
                'Failed to load attributes',
                () => ref.invalidate(provider),
              ),
            ),
            loading: () => SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                DesignTokens.spacing16,
                DesignTokens.spacing4,
                DesignTokens.spacing16,
                DesignTokens.bottomScrollPadding(context),
              ),
              child: const TbShimmerList(itemCount: 4),
            ),
            data: (attributes) {
              if (attributes.isEmpty) {
                return _bottomSafeState(
                  const TbEmptyState(
                    icon: TbIconKind.attributesTag,
                    title: 'No attributes in scope',
                    subtitle: 'Select another attribute scope above.',
                  ),
                );
              }
              return _tabList([
                TbSectionCard(
                  title: 'Attributes',
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final attr in attributes)
                        TbKvRow(label: attr.key, value: attr.displayValue),
                    ],
                  ),
                ),
              ], topPadding: DesignTokens.spacing4);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildAlarmsTab() {
    final alarmsAsync = ref.watch(alarmsListProvider(_entityId));

    return alarmsAsync.when(
      error: (e, _) => _bottomSafeState(
        _errorState(
          'Failed to load alarms',
          () => ref.invalidate(alarmsListProvider(_entityId)),
        ),
      ),
      loading: () => SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          DesignTokens.spacing16,
          DesignTokens.spacing16,
          DesignTokens.spacing16,
          DesignTokens.bottomScrollPadding(context),
        ),
        child: const TbShimmerList(itemCount: 3),
      ),
      data: (pagedAlarms) {
        if (pagedAlarms.items.isEmpty) {
          return _bottomSafeState(
            const TbEmptyState(
              icon: TbIconKind.severityCritical,
              title: 'No active alarms',
              subtitle: 'This asset has no triggered alarms.',
            ),
          );
        }
        return _tabList([
          TbSectionCard(
            title: 'Alarms',
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final alarm in pagedAlarms.items)
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TbListRow(
                        title: alarm.type,
                        meta: alarm.createdTime > 0
                            ? DateFormat.yMMMd().add_jm().format(
                                DateTime.fromMillisecondsSinceEpoch(
                                  alarm.createdTime,
                                ),
                              )
                            : null,
                        leading: TbStatusBadge.severity(
                          alarm.severity,
                          compact: true,
                        ),
                      ),
                      if (!alarm.acknowledged || !alarm.cleared)
                        Align(
                          alignment: AlignmentDirectional.centerEnd,
                          child: Wrap(
                            alignment: WrapAlignment.end,
                            spacing: DesignTokens.spacing8,
                            runSpacing: DesignTokens.spacing8,
                            children: [
                              if (!alarm.acknowledged)
                                TextButton(
                                  onPressed: () => ref
                                      .read(
                                        alarmsListProvider(_entityId).notifier,
                                      )
                                      .acknowledge(alarm.id),
                                  child: const Text('Acknowledge'),
                                ),
                              if (!alarm.cleared)
                                FilledButton.tonal(
                                  onPressed: () => ref
                                      .read(
                                        alarmsListProvider(_entityId).notifier,
                                      )
                                      .clear(alarm.id),
                                  child: const Text('Clear'),
                                ),
                            ],
                          ),
                        ),
                    ],
                  ),
              ],
            ),
          ),
        ]);
      },
    );
  }

  Widget _buildRelationsTab() {
    final provider = entityRelationsProvider((
      entity: _entityId,
      outgoing: true,
    ));
    final relationsAsync = ref.watch(provider);
    final scheme = Theme.of(context).colorScheme;

    return relationsAsync.when(
      error: (e, _) => _bottomSafeState(
        _errorState('Failed to load relations', () => ref.invalidate(provider)),
      ),
      loading: () => SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          DesignTokens.spacing16,
          DesignTokens.spacing16,
          DesignTokens.spacing16,
          DesignTokens.bottomScrollPadding(context),
        ),
        child: const TbShimmerList(itemCount: 3),
      ),
      data: (relations) {
        if (relations.isEmpty) {
          return _bottomSafeState(
            const TbEmptyState(
              icon: TbIconKind.relationsGraph,
              title: 'No relations found',
              subtitle: 'Contained devices and assets will appear here.',
            ),
          );
        }
        return _tabList([
          TbSectionCard(
            title: 'Relations',
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final rel in relations) _relationRow(rel, scheme),
              ],
            ),
          ),
        ]);
      },
    );
  }

  Widget _relationRow(TbEntityRelationInfo rel, ColorScheme scheme) {
    final isDevice = rel.to.entityType == EntityType.device;
    final isAsset = rel.to.entityType == EntityType.asset;
    final route = isDevice
        ? AppRoutes.deviceDetailsPath(rel.to.id)
        : isAsset
        ? AppRoutes.assetDetailsPath(rel.to.id)
        : null;

    return TbListRow(
      title: rel.toName.isNotEmpty ? rel.toName : rel.to.id,
      meta: '${rel.type} · ${rel.to.entityType.wireValue}',
      leading: TbIcon(
        isDevice ? TbIconKind.sensorNode : TbIconKind.assetBuilding,
        color: scheme.primary,
        size: DesignTokens.iconMedium,
      ),
      trailing: route == null
          ? null
          : Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
      onTap: route == null
          ? null
          : () {
              if (GoRouter.maybeOf(context) != null) context.push(route);
            },
    );
  }
}

class _TabBarHeaderDelegate extends SliverPersistentHeaderDelegate {
  _TabBarHeaderDelegate(this.tabBar, {required this.color});

  final TabBar tabBar;
  final Color color;

  @override
  double get minExtent => tabBar.preferredSize.height;

  @override
  double get maxExtent => tabBar.preferredSize.height;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return Container(color: color, child: tabBar);
  }

  @override
  bool shouldRebuild(covariant _TabBarHeaderDelegate oldDelegate) {
    return tabBar != oldDelegate.tabBar || color != oldDelegate.color;
  }
}

class _AssetDetailsShimmer extends StatelessWidget {
  const _AssetDetailsShimmer();

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        DesignTokens.spacing16,
        DesignTokens.spacing16,
        DesignTokens.spacing16,
        DesignTokens.bottomScrollPadding(context),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: const [
          TbShimmer(height: 84),
          SizedBox(height: DesignTokens.spacing16),
          TbShimmer(height: 48),
          SizedBox(height: DesignTokens.spacing16),
          TbShimmerList(itemCount: 3),
        ],
      ),
    );
  }
}
