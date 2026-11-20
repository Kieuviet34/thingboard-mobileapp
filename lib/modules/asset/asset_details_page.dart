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
import 'package:thingsboard_democloud_app/widgets/tb_metric_pill.dart';
import 'package:thingsboard_democloud_app/widgets/tb_motion.dart';
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
        return TbEmptyState(
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
        );
      },
    );

    if (widget.embedded) {
      return Container(color: scheme.surface, child: content);
    }

    final title = assetAsync.valueOrNull?.name ?? 'Asset Details';
    return Scaffold(
      appBar: TbAppBar(canGoBack: true, title: Text(title)),
      body: SafeArea(child: content),
    );
  }

  Widget _buildAssetContent(BuildContext context, TbAssetInfo asset) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

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
                child: Material(
                  color: scheme.surfaceContainerLow,
                  shape: RoundedRectangleBorder(
                    borderRadius: DesignTokens.borderRadiusLarge,
                    side: BorderSide(color: scheme.outlineVariant),
                  ),
                  child: Padding(
                    padding: DesignTokens.cardPadding,
                    child: Row(
                      children: [
                        Container(
                          width: 52,
                          height: 52,
                          decoration: BoxDecoration(
                            color: scheme.primaryContainer,
                            borderRadius: DesignTokens.borderRadiusMedium,
                          ),
                          child: Center(
                            child: TbIcon(
                              TbIconKind.assetBuilding,
                              size: DesignTokens.iconLarge,
                              color: scheme.onPrimaryContainer,
                            ),
                          ),
                        ),
                        const SizedBox(width: DesignTokens.spacing16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                asset.name,
                                style: textTheme.titleMedium?.copyWith(
                                  color: scheme.onSurface,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: DesignTokens.spacing4),
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: DesignTokens.spacing8,
                                      vertical: DesignTokens.spacing2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: scheme.surfaceContainerHigh,
                                      borderRadius:
                                          DesignTokens.borderRadiusRound,
                                    ),
                                    child: Text(
                                      asset.type,
                                      style: textTheme.labelSmall?.copyWith(
                                        color: scheme.onSurfaceVariant,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                  if (asset.ownerName.isNotEmpty) ...[
                                    const SizedBox(
                                      width: DesignTokens.spacing8,
                                    ),
                                    Expanded(
                                      child: Text(
                                        asset.ownerName,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: textTheme.bodySmall?.copyWith(
                                          color: scheme.onSurfaceVariant,
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            SliverPersistentHeader(
              pinned: true,
              delegate: _TabBarHeaderDelegate(
                TabBar(
                  controller: _tabController,
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
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: DesignTokens.paddingMedium,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            telemetryAsync.when(
              error: (e, _) => Text(
                'Failed to load telemetry',
                style: textTheme.bodyMedium?.copyWith(color: scheme.error),
              ),
              loading: () => const TbShimmerList(itemCount: 2),
              data: (latest) {
                if (latest.isEmpty) {
                  return const TbEmptyState(
                    icon: TbIconKind.sensorNode,
                    title: 'No telemetry values',
                    subtitle: 'Latest metric readings will appear here.',
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
            const SizedBox(height: DesignTokens.spacing24),
            Text(
              'History (24 Hours)',
              style: textTheme.labelLarge?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: DesignTokens.spacing8),
            historyAsync.when(
              error: (e, _) => Text(
                'Failed to load chart history',
                style: textTheme.bodyMedium?.copyWith(color: scheme.error),
              ),
              loading: () => const TbShimmer(height: 96),
              data: (history) {
                if (history.isEmpty) {
                  return const Text('No history points recorded.');
                }
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final entry in history.entries) ...[
                      Material(
                        color: scheme.surfaceContainerLow,
                        shape: RoundedRectangleBorder(
                          borderRadius: DesignTokens.borderRadiusLarge,
                          side: BorderSide(color: scheme.outlineVariant),
                        ),
                        child: Padding(
                          padding: DesignTokens.cardPadding,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                entry.key,
                                style: textTheme.titleSmall?.copyWith(
                                  color: scheme.onSurface,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: DesignTokens.spacing12),
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
                        ),
                      ),
                      const SizedBox(height: DesignTokens.spacing8),
                    ],
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAttributesTab() {
    final attributesAsync = ref.watch(
      entityAttributesProvider((id: _entityId, scope: _attributeScope)),
    );
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: DesignTokens.spacing16,
            vertical: DesignTokens.spacing8,
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final scope in TbAttributeScope.values) ...[
                  FilterChip(
                    label: Text(scope.label),
                    selected: _attributeScope == scope,
                    onSelected: (_) => setState(() => _attributeScope = scope),
                  ),
                  const SizedBox(width: DesignTokens.spacing8),
                ],
              ],
            ),
          ),
        ),
        Expanded(
          child: attributesAsync.when(
            error: (e, _) => Center(
              child: Text(
                'Failed to load attributes',
                style: textTheme.bodyMedium?.copyWith(color: scheme.error),
              ),
            ),
            loading: () => const SingleChildScrollView(
              padding: DesignTokens.paddingMedium,
              child: TbShimmerList(itemCount: 4),
            ),
            data: (attributes) {
              if (attributes.isEmpty) {
                return const TbEmptyState(
                  icon: TbIconKind.attributesTag,
                  title: 'No attributes in scope',
                  subtitle: 'Select another attribute scope above.',
                );
              }
              return ListView.separated(
                padding: DesignTokens.paddingMedium,
                itemCount: attributes.length,
                separatorBuilder: (_, _) =>
                    const SizedBox(height: DesignTokens.spacing8),
                itemBuilder: (context, index) {
                  final attr = attributes[index];
                  return Material(
                    color: scheme.surfaceContainerLow,
                    shape: RoundedRectangleBorder(
                      borderRadius: DesignTokens.borderRadiusLarge,
                      side: BorderSide(color: scheme.outlineVariant),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: DesignTokens.spacing16,
                        vertical: DesignTokens.spacing12,
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              attr.key,
                              style: textTheme.bodyMedium?.copyWith(
                                color: scheme.onSurface,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                          const SizedBox(width: DesignTokens.spacing12),
                          Flexible(
                            child: Text(
                              attr.displayValue,
                              textAlign: TextAlign.end,
                              style: textTheme.bodyMedium?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildAlarmsTab() {
    final alarmsAsync = ref.watch(alarmsListProvider(_entityId));
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return alarmsAsync.when(
      error: (e, _) => Center(
        child: Text(
          'Failed to load alarms',
          style: textTheme.bodyMedium?.copyWith(color: scheme.error),
        ),
      ),
      loading: () => const SingleChildScrollView(
        padding: DesignTokens.paddingMedium,
        child: TbShimmerList(itemCount: 3),
      ),
      data: (pagedAlarms) {
        if (pagedAlarms.items.isEmpty) {
          return const TbEmptyState(
            icon: TbIconKind.severityCritical,
            title: 'No active alarms',
            subtitle: 'This asset has no triggered alarms.',
          );
        }
        return ListView.separated(
          padding: DesignTokens.paddingMedium,
          itemCount: pagedAlarms.items.length,
          separatorBuilder: (_, _) =>
              const SizedBox(height: DesignTokens.spacing8),
          itemBuilder: (context, index) {
            final alarm = pagedAlarms.items[index];
            final dateStr = alarm.createdTime > 0
                ? DateFormat.yMMMd().add_jm().format(
                    DateTime.fromMillisecondsSinceEpoch(alarm.createdTime),
                  )
                : '';

            return Material(
              color: scheme.surfaceContainerLow,
              shape: RoundedRectangleBorder(
                borderRadius: DesignTokens.borderRadiusLarge,
                side: BorderSide(color: scheme.outlineVariant),
              ),
              child: Padding(
                padding: DesignTokens.cardPadding,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        TbStatusBadge.severity(alarm.severity, compact: true),
                        const SizedBox(width: DesignTokens.spacing8),
                        Expanded(
                          child: Text(
                            alarm.type,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: textTheme.titleSmall?.copyWith(
                              color: scheme.onSurface,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (dateStr.isNotEmpty) ...[
                      const SizedBox(height: DesignTokens.spacing4),
                      Text(
                        dateStr,
                        style: textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                    const SizedBox(height: DesignTokens.spacing8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        if (!alarm.acknowledged)
                          TextButton(
                            onPressed: () => ref
                                .read(alarmsListProvider(_entityId).notifier)
                                .acknowledge(alarm.id),
                            child: const Text('Acknowledge'),
                          ),
                        if (!alarm.cleared) ...[
                          const SizedBox(width: DesignTokens.spacing8),
                          FilledButton.tonal(
                            onPressed: () => ref
                                .read(alarmsListProvider(_entityId).notifier)
                                .clear(alarm.id),
                            child: const Text('Clear'),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildRelationsTab() {
    final relationsAsync = ref.watch(
      entityRelationsProvider((entity: _entityId, outgoing: true)),
    );
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return relationsAsync.when(
      error: (e, _) => Center(
        child: Text(
          'Failed to load relations',
          style: textTheme.bodyMedium?.copyWith(color: scheme.error),
        ),
      ),
      loading: () => const SingleChildScrollView(
        padding: DesignTokens.paddingMedium,
        child: TbShimmerList(itemCount: 3),
      ),
      data: (relations) {
        if (relations.isEmpty) {
          return const TbEmptyState(
            icon: TbIconKind.relationsGraph,
            title: 'No relations found',
            subtitle: 'Contained devices and assets will appear here.',
          );
        }
        return ListView.separated(
          padding: DesignTokens.paddingMedium,
          itemCount: relations.length,
          separatorBuilder: (_, _) =>
              const SizedBox(height: DesignTokens.spacing8),
          itemBuilder: (context, index) {
            final rel = relations[index];
            final isDevice = rel.to.entityType == EntityType.device;
            final isAsset = rel.to.entityType == EntityType.asset;

            return Material(
              color: scheme.surfaceContainerLow,
              shape: RoundedRectangleBorder(
                borderRadius: DesignTokens.borderRadiusLarge,
                side: BorderSide(color: scheme.outlineVariant),
              ),
              child: InkWell(
                borderRadius: DesignTokens.borderRadiusLarge,
                onTap: isDevice
                    ? () {
                        final router = GoRouter.maybeOf(context);
                        if (router != null) {
                          context.push(AppRoutes.deviceDetailsPath(rel.to.id));
                        }
                      }
                    : isAsset
                    ? () {
                        final router = GoRouter.maybeOf(context);
                        if (router != null) {
                          context.push(AppRoutes.assetDetailsPath(rel.to.id));
                        }
                      }
                    : null,
                child: Padding(
                  padding: DesignTokens.cardPadding,
                  child: Row(
                    children: [
                      TbIcon(
                        isDevice
                            ? TbIconKind.sensorNode
                            : TbIconKind.assetBuilding,
                        color: scheme.primary,
                        size: DesignTokens.iconMedium,
                      ),
                      const SizedBox(width: DesignTokens.spacing12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              rel.toName.isNotEmpty ? rel.toName : rel.to.id,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: textTheme.bodyLarge?.copyWith(
                                color: scheme.onSurface,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            Text(
                              '${rel.type} · ${rel.to.entityType.wireValue}',
                              style: textTheme.bodySmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (isDevice || isAsset)
                        Icon(
                          Icons.chevron_right,
                          color: scheme.onSurfaceVariant,
                        ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
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
      padding: DesignTokens.paddingMedium,
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
