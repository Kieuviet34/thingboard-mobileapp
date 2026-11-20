import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:thingsboard_democloud_app/config/routes/router.dart';
import 'package:thingsboard_democloud_app/config/themes/design_tokens.dart';
import 'package:thingsboard_democloud_app/config/themes/tb_status_colors.dart';
import 'package:thingsboard_democloud_app/config/themes/tb_text_styles.dart';
import 'package:thingsboard_democloud_app/core/api/controllers/alarm_controller.dart';
import 'package:thingsboard_democloud_app/core/api/controllers/dashboard_controller.dart';
import 'package:thingsboard_democloud_app/core/api/controllers/device_controller.dart';
import 'package:thingsboard_democloud_app/core/api/controllers/server_config_controller.dart';
import 'package:thingsboard_democloud_app/core/api/ws/telemetry_ws_service.dart';
import 'package:thingsboard_democloud_app/core/models/auth_models.dart';
import 'package:thingsboard_democloud_app/core/models/dashboard_models.dart';
import 'package:thingsboard_democloud_app/core/models/tb_failure.dart';
import 'package:thingsboard_democloud_app/widgets/icons/tb_icons.dart';
import 'package:thingsboard_democloud_app/widgets/tb_app_bar.dart';
import 'package:thingsboard_democloud_app/widgets/tb_empty_state.dart';
import 'package:thingsboard_democloud_app/widgets/tb_metric_pill.dart';
import 'package:thingsboard_democloud_app/widgets/tb_motion.dart';
import 'package:thingsboard_democloud_app/widgets/tb_shimmer.dart';
import 'package:thingsboard_democloud_app/widgets/tb_status_badge.dart';

/// Minimal-text Material 3 IoT command center for Shell Branch 0 (`/home`).
class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  Future<void> _refreshAll(WidgetRef ref) async {
    ref.invalidate(homeDashboardProvider);
    ref.invalidate(userDashboardsInfoProvider);
    ref.invalidate(alarmsListProvider(null));
    ref.invalidate(deviceProfilesListProvider);
    await ref.read(dashboardsListProvider(null).notifier).refresh();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(serverConfigProvider.select((s) => s.mode));
    final wsState = ref.watch(wsConnectionStateProvider).valueOrNull;
    final dashboardsAsync = ref.watch(dashboardsListProvider(null));
    final homeInfo = ref.watch(homeDashboardProvider).valueOrNull;
    final userDashInfo = ref.watch(userDashboardsInfoProvider).valueOrNull;
    final alarmsAsync = ref.watch(alarmsListProvider(null));
    final profilesAsync = ref.watch(deviceProfilesListProvider);

    final isDemo = mode == SessionMode.demo;
    final isWsOnline = wsState == WsConnectionState.authenticated;

    return Scaffold(
      appBar: TbAppBar(
        canGoBack: false,
        title: const Text('Home'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: DesignTokens.spacing4),
            child: Center(
              child: isDemo
                  ? TbStatusBadge.demo(compact: true)
                  : TbStatusBadge(
                      label: isWsOnline ? 'LIVE' : 'OFFLINE',
                      icon: isWsOnline
                          ? TbIconKind.livePulse
                          : TbIconKind.offlineNode,
                      tone: isWsOnline
                          ? TbStatusTone.online
                          : TbStatusTone.offline,
                      compact: true,
                    ),
            ),
          ),
          IconButton(
            tooltip: 'All dashboards',
            constraints: const BoxConstraints(
              minWidth: DesignTokens.minTouchTarget,
              minHeight: DesignTokens.minTouchTarget,
            ),
            icon: const TbIcon(TbIconKind.dashboardTile),
            onPressed: () => context.push(AppRoutes.dashboards),
          ),
        ],
      ),
      body: SafeArea(
        child: dashboardsAsync.when(
          loading: () => const SingleChildScrollView(
            padding: DesignTokens.paddingMedium,
            child: TbShimmerList(itemCount: 3),
          ),
          error: (error, _) => TbEmptyState(
            icon: TbIconKind.dashboardTile,
            title: 'Failed to load',
            subtitle: error is TbFailure ? error.message : null,
            actionLabel: 'Retry',
            isError: true,
            onAction: () => _refreshAll(ref),
          ),
          data: (paged) {
            final dashboards = paged.items;
            final alarms = alarmsAsync.valueOrNull?.items ?? const [];
            final activeAlarms = alarms.where((a) => !a.cleared).length;
            final profiles = profilesAsync.valueOrNull?.items ?? const [];
            final onlineDevices = profiles.fold<int>(
              0,
              (acc, p) => acc + p.activeCount,
            );
            final offlineDevices = profiles.fold<int>(
              0,
              (acc, p) => acc + p.inactiveCount,
            );

            final spotlightId = homeInfo?.dashboardId;
            final spotlight = spotlightId != null
                ? dashboards.where((d) => d.id == spotlightId).firstOrNull ??
                      dashboards.firstOrNull
                : dashboards.firstOrNull;

            final recentOrder = <String, int>{
              for (var i = 0; i < (userDashInfo?.last.length ?? 0); i++)
                userDashInfo!.last[i].id: i,
            };
            final otherDashboards =
                dashboards
                    .where((d) => d.id != spotlight?.id)
                    .toList(growable: false)
                  ..sort((a, b) {
                    if (a.isStarred != b.isStarred) {
                      return a.isStarred ? -1 : 1;
                    }
                    final rankA = recentOrder[a.id] ?? 9999;
                    final rankB = recentOrder[b.id] ?? 9999;
                    return rankA.compareTo(rankB);
                  });

            return RefreshIndicator(
              onRefresh: () => _refreshAll(ref),
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  SliverPadding(
                    padding: DesignTokens.paddingMedium,
                    sliver: SliverList(
                      delegate: SliverChildListDelegate([
                        TbStaggeredEntry(
                          index: 0,
                          child: _HomeKpiStrip(
                            activeAlarms: activeAlarms,
                            onlineDevices: onlineDevices,
                            offlineDevices: offlineDevices,
                            isLoadingAlarms: alarmsAsync.isLoading,
                            isLoadingDevices: profilesAsync.isLoading,
                          ),
                        ),
                        const SizedBox(height: DesignTokens.spacing16),
                        if (dashboards.isEmpty)
                          TbEmptyState(
                            icon: TbIconKind.dashboardTile,
                            title: 'No dashboards',
                            actionLabel: 'Refresh',
                            onAction: () => _refreshAll(ref),
                          )
                        else ...[
                          if (spotlight != null) ...[
                            _SectionHeader(
                              title: 'Home dashboard',
                              trailingLabel: 'See all',
                              onTrailingTap: () =>
                                  context.push(AppRoutes.dashboards),
                            ),
                            const SizedBox(height: DesignTokens.spacing8),
                            TbStaggeredEntry(
                              index: 1,
                              child: _HomeSpotlightCard(
                                dashboard: spotlight,
                                onOpen: () => context.push(
                                  AppRoutes.dashboardDetailsPath(spotlight.id),
                                ),
                                onToggleStar: () => ref
                                    .read(dashboardsListProvider(null).notifier)
                                    .toggleStar(spotlight.id),
                              ),
                            ),
                            const SizedBox(height: DesignTokens.spacing16),
                          ],
                          if (otherDashboards.isNotEmpty) ...[
                            const _SectionHeader(title: 'Starred & recent'),
                            const SizedBox(height: DesignTokens.spacing8),
                            _ResponsiveDashboardGrid(
                              dashboards: otherDashboards,
                              startIndex: 2,
                              keyPrefix: 'home',
                              onOpen: (id) => context.push(
                                AppRoutes.dashboardDetailsPath(id),
                              ),
                              onToggleStar: (id) => ref
                                  .read(dashboardsListProvider(null).notifier)
                                  .toggleStar(id),
                            ),
                          ],
                        ],
                      ]),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    this.trailingLabel,
    this.onTrailingTap,
  });

  final String title;
  final String? trailingLabel;
  final VoidCallback? onTrailingTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: textTheme.titleSmall?.copyWith(
              color: scheme.onSurface,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        if (trailingLabel != null && onTrailingTap != null)
          TextButton(
            style: TextButton.styleFrom(
              minimumSize: const Size(
                DesignTokens.minTouchTarget,
                DesignTokens.minTouchTarget,
              ),
            ),
            onPressed: onTrailingTap,
            child: Text(trailingLabel!),
          ),
      ],
    );
  }
}

class _HomeKpiStrip extends StatelessWidget {
  const _HomeKpiStrip({
    required this.activeAlarms,
    required this.onlineDevices,
    required this.offlineDevices,
    required this.isLoadingAlarms,
    required this.isLoadingDevices,
  });

  final int activeAlarms;
  final int onlineDevices;
  final int offlineDevices;
  final bool isLoadingAlarms;
  final bool isLoadingDevices;

  @override
  Widget build(BuildContext context) {
    final statusColors = TbStatusColors.of(context);
    final totalDevices = onlineDevices + offlineDevices;

    return LayoutBuilder(
      builder: (context, constraints) {
        final useSingleColumn = constraints.maxWidth < 280;
        final alarmsTile = _KpiTile(
          tileKey: const Key('home-kpi-alarms'),
          icon: TbIconKind.navAlarms,
          accentColor: activeAlarms > 0
              ? statusColors.critical
              : statusColors.cleared,
          label: 'Alarms',
          value: '$activeAlarms',
          caption: activeAlarms > 0 ? 'Active' : 'Clear',
          semanticLabel: 'Alarms: $activeAlarms active',
          isLoading: isLoadingAlarms,
          onTap: () => context.go(AppRoutes.alarms),
        );
        final devicesTile = _KpiTile(
          tileKey: const Key('home-kpi-devices'),
          icon: TbIconKind.navDevices,
          accentColor: onlineDevices > 0
              ? statusColors.online
              : statusColors.offline,
          label: 'Devices',
          value: '$onlineDevices/$totalDevices',
          caption: '$offlineDevices offline',
          semanticLabel:
              'Devices: $onlineDevices online, $offlineDevices offline',
          isLoading: isLoadingDevices,
          onTap: () => context.go(AppRoutes.devices),
        );

        if (useSingleColumn) {
          return Column(
            children: [
              alarmsTile,
              const SizedBox(height: DesignTokens.spacing12),
              devicesTile,
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: alarmsTile),
            const SizedBox(width: DesignTokens.spacing12),
            Expanded(child: devicesTile),
          ],
        );
      },
    );
  }
}

class _KpiTile extends StatelessWidget {
  const _KpiTile({
    required this.tileKey,
    required this.icon,
    required this.accentColor,
    required this.label,
    required this.value,
    required this.caption,
    required this.semanticLabel,
    required this.isLoading,
    required this.onTap,
  });

  final Key tileKey;
  final TbIconKind icon;
  final Color accentColor;
  final String label;
  final String value;
  final String caption;
  final String semanticLabel;
  final bool isLoading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Semantics(
      button: true,
      label: semanticLabel,
      child: TbPressScale(
        onTap: onTap,
        borderRadius: DesignTokens.borderRadiusXl,
        child: Container(
          key: tileKey,
          constraints: const BoxConstraints(
            minHeight: DesignTokens.minTouchTarget,
          ),
          padding: DesignTokens.cardPadding,
          decoration: BoxDecoration(
            color: scheme.surfaceContainerLow,
            borderRadius: DesignTokens.borderRadiusXl,
            border: Border.all(color: scheme.outlineVariant),
          ),
          child: isLoading
              ? const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TbShimmer(width: 64, height: 14),
                    SizedBox(height: DesignTokens.spacing8),
                    TbShimmer(width: 48, height: 24),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        TbIcon(
                          icon,
                          size: DesignTokens.iconSmall,
                          color: accentColor,
                          filled: true,
                        ),
                        const SizedBox(width: DesignTokens.spacing8),
                        Expanded(
                          child: Text(
                            label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: textTheme.labelMedium?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: DesignTokens.spacing8),
                    Text(
                      value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          TbTextStyles.tabular(
                            textTheme.headlineSmall ?? TbTextStyles.titleMedium,
                          ).copyWith(
                            color: scheme.onSurface,
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    const SizedBox(height: DesignTokens.spacing2),
                    Text(
                      caption,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.labelSmall?.copyWith(color: accentColor),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

class _HomeSpotlightCard extends StatelessWidget {
  const _HomeSpotlightCard({
    required this.dashboard,
    required this.onOpen,
    required this.onToggleStar,
  });

  final TbDashboardInfo dashboard;
  final VoidCallback onOpen;
  final VoidCallback onToggleStar;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final metrics = dashboard.metrics.entries.take(4).toList(growable: false);

    return Semantics(
      button: true,
      label: 'Home dashboard ${dashboard.title}',
      child: TbPressScale(
        onTap: onOpen,
        borderRadius: DesignTokens.borderRadiusXl,
        child: Container(
          key: Key('home-spotlight-${dashboard.id}'),
          padding: DesignTokens.cardPadding,
          decoration: BoxDecoration(
            color: scheme.primaryContainer.withValues(alpha: 0.35),
            borderRadius: DesignTokens.borderRadiusXl,
            border: Border.all(color: scheme.primary.withValues(alpha: 0.25)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Hero(
                    tag: 'dashboard-${dashboard.id}',
                    child: Container(
                      padding: DesignTokens.paddingSmall,
                      decoration: BoxDecoration(
                        color: scheme.primaryContainer,
                        borderRadius: DesignTokens.borderRadiusLarge,
                      ),
                      child: TbIcon(
                        TbIconKind.dashboardTile,
                        size: DesignTokens.iconMedium,
                        color: scheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                  const SizedBox(width: DesignTokens.spacing12),
                  Expanded(
                    child: Text(
                      dashboard.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.titleMedium?.copyWith(
                        color: scheme.onSurface,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  IconButton(
                    key: Key('home-spotlight-star-${dashboard.id}'),
                    tooltip: dashboard.isStarred ? 'Unstar' : 'Star',
                    constraints: const BoxConstraints(
                      minWidth: DesignTokens.minTouchTarget,
                      minHeight: DesignTokens.minTouchTarget,
                    ),
                    icon: Icon(
                      dashboard.isStarred
                          ? Icons.star_rounded
                          : Icons.star_outline_rounded,
                      color: dashboard.isStarred
                          ? scheme.tertiary
                          : scheme.onSurfaceVariant,
                    ),
                    onPressed: onToggleStar,
                  ),
                ],
              ),
              if (metrics.isNotEmpty) ...[
                const SizedBox(height: DesignTokens.spacing12),
                Wrap(
                  spacing: DesignTokens.spacing8,
                  runSpacing: DesignTokens.spacing8,
                  children: [
                    for (final entry in metrics)
                      TbMetricPill(
                        icon: TbIcons.kindForTelemetryKey(entry.key),
                        label: entry.key,
                        value: entry.value,
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ResponsiveDashboardGrid extends StatelessWidget {
  const _ResponsiveDashboardGrid({
    required this.dashboards,
    required this.startIndex,
    required this.keyPrefix,
    required this.onOpen,
    required this.onToggleStar,
  });

  final List<TbDashboardInfo> dashboards;
  final int startIndex;
  final String keyPrefix;
  final ValueChanged<String> onOpen;
  final ValueChanged<String> onToggleStar;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= DesignTokens.mediumMaxWidth
            ? 3
            : (constraints.maxWidth >= 320 ? 2 : 1);
        final spacing = DesignTokens.spacing12;
        final cardWidth =
            (constraints.maxWidth - spacing * (columns - 1)) / columns;

        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (var i = 0; i < dashboards.length; i++)
              SizedBox(
                width: cardWidth,
                child: TbStaggeredEntry(
                  index: startIndex + i,
                  child: _CompactDashboardCard(
                    dashboard: dashboards[i],
                    keyPrefix: keyPrefix,
                    onOpen: () => onOpen(dashboards[i].id),
                    onToggleStar: () => onToggleStar(dashboards[i].id),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _CompactDashboardCard extends StatelessWidget {
  const _CompactDashboardCard({
    required this.dashboard,
    required this.keyPrefix,
    required this.onOpen,
    required this.onToggleStar,
  });

  final TbDashboardInfo dashboard;
  final String keyPrefix;
  final VoidCallback onOpen;
  final VoidCallback onToggleStar;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final firstMetric = dashboard.metrics.entries.firstOrNull;

    return Semantics(
      button: true,
      label: dashboard.title,
      child: TbPressScale(
        onTap: onOpen,
        borderRadius: DesignTokens.borderRadiusLarge,
        child: Container(
          key: Key('$keyPrefix-card-${dashboard.id}'),
          padding: DesignTokens.paddingMedium,
          decoration: BoxDecoration(
            color: scheme.surfaceContainerLow,
            borderRadius: DesignTokens.borderRadiusLarge,
            border: Border.all(color: scheme.outlineVariant),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  TbIcon(
                    TbIconKind.dashboardTile,
                    size: DesignTokens.iconSmall,
                    color: scheme.primary,
                  ),
                  const Spacer(),
                  IconButton(
                    key: Key('$keyPrefix-star-${dashboard.id}'),
                    tooltip: dashboard.isStarred ? 'Unstar' : 'Star',
                    constraints: const BoxConstraints(
                      minWidth: DesignTokens.minTouchTarget,
                      minHeight: DesignTokens.minTouchTarget,
                    ),
                    padding: DesignTokens.paddingZero,
                    icon: Icon(
                      dashboard.isStarred
                          ? Icons.star_rounded
                          : Icons.star_outline_rounded,
                      color: dashboard.isStarred
                          ? scheme.tertiary
                          : scheme.onSurfaceVariant,
                    ),
                    onPressed: onToggleStar,
                  ),
                ],
              ),
              const SizedBox(height: DesignTokens.spacing4),
              Text(
                dashboard.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: textTheme.titleSmall?.copyWith(
                  color: scheme.onSurface,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (firstMetric != null) ...[
                const SizedBox(height: DesignTokens.spacing8),
                TbMetricPill(
                  icon: TbIcons.kindForTelemetryKey(firstMetric.key),
                  value: firstMetric.value,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
