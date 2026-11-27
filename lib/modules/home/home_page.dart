import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:thingsboard_democloud_app/config/routes/router.dart';
import 'package:thingsboard_democloud_app/config/themes/design_tokens.dart';
import 'package:thingsboard_democloud_app/config/themes/tb_status_colors.dart';
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
import 'package:thingsboard_democloud_app/widgets/tb_list_row.dart';
import 'package:thingsboard_democloud_app/widgets/tb_metric_pill.dart';
import 'package:thingsboard_democloud_app/widgets/tb_motion.dart';
import 'package:thingsboard_democloud_app/widgets/tb_section_card.dart';
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
    final scrollPadding = EdgeInsets.fromLTRB(
      DesignTokens.spacing16,
      DesignTokens.spacing16,
      DesignTokens.spacing16,
      DesignTokens.bottomScrollPadding(context),
    );

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
        bottom: false,
        child: dashboardsAsync.when(
          loading: () => SingleChildScrollView(
            padding: scrollPadding,
            child: const TbShimmerList(itemCount: 3),
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
                    padding: scrollPadding,
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
                            TbStaggeredEntry(
                              index: 1,
                              child: TbSectionCard(
                                title: 'Home dashboard',
                                trailing: TextButton(
                                  style: TextButton.styleFrom(
                                    minimumSize: const Size(
                                      DesignTokens.minTouchTarget,
                                      DesignTokens.minTouchTarget,
                                    ),
                                  ),
                                  onPressed: () =>
                                      context.push(AppRoutes.dashboards),
                                  child: const Text('See all'),
                                ),
                                child: _HomeSpotlight(
                                  dashboard: spotlight,
                                  onOpen: () => context.push(
                                    AppRoutes.dashboardDetailsPath(
                                      spotlight.id,
                                    ),
                                  ),
                                  onToggleStar: () => ref
                                      .read(
                                        dashboardsListProvider(null).notifier,
                                      )
                                      .toggleStar(spotlight.id),
                                ),
                              ),
                            ),
                            const SizedBox(height: DesignTokens.spacing16),
                          ],
                          if (otherDashboards.isNotEmpty)
                            TbSectionCard(
                              title: 'Starred & recent',
                              child: Column(
                                children: [
                                  for (
                                    var i = 0;
                                    i < otherDashboards.length;
                                    i++
                                  )
                                    TbStaggeredEntry(
                                      index: 2 + i,
                                      child: _DashboardRow(
                                        dashboard: otherDashboards[i],
                                        onOpen: () => context.push(
                                          AppRoutes.dashboardDetailsPath(
                                            otherDashboards[i].id,
                                          ),
                                        ),
                                        onToggleStar: () => ref
                                            .read(
                                              dashboardsListProvider(
                                                null,
                                              ).notifier,
                                            )
                                            .toggleStar(otherDashboards[i].id),
                                      ),
                                    ),
                                ],
                              ),
                            ),
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

/// Overview section: tappable alarm and device summary pills.
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

    return TbSectionCard(
      title: 'Overview',
      child: Wrap(
        spacing: DesignTokens.spacing12,
        runSpacing: DesignTokens.spacing12,
        children: [
          _KpiPill(
            tileKey: const Key('home-kpi-alarms'),
            icon: TbIconKind.navAlarms,
            accentColor: activeAlarms > 0
                ? statusColors.critical
                : statusColors.cleared,
            label: 'Alarms',
            value: '$activeAlarms',
            unit: activeAlarms > 0 ? 'active' : 'clear',
            semanticLabel: 'Alarms: $activeAlarms active',
            isLoading: isLoadingAlarms,
            onTap: () => context.go(AppRoutes.alarms),
          ),
          _KpiPill(
            tileKey: const Key('home-kpi-devices'),
            icon: TbIconKind.navDevices,
            accentColor: onlineDevices > 0
                ? statusColors.online
                : statusColors.offline,
            label: 'Devices',
            value: '$onlineDevices/$totalDevices',
            unit: 'online',
            semanticLabel:
                'Devices: $onlineDevices online, $offlineDevices offline',
            isLoading: isLoadingDevices,
            onTap: () => context.go(AppRoutes.devices),
          ),
        ],
      ),
    );
  }
}

class _KpiPill extends StatelessWidget {
  const _KpiPill({
    required this.tileKey,
    required this.icon,
    required this.accentColor,
    required this.label,
    required this.value,
    required this.unit,
    required this.semanticLabel,
    required this.isLoading,
    required this.onTap,
  });

  final Key tileKey;
  final TbIconKind icon;
  final Color accentColor;
  final String label;
  final String value;
  final String unit;
  final String semanticLabel;
  final bool isLoading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: semanticLabel,
      excludeSemantics: true,
      child: InkWell(
        key: tileKey,
        onTap: onTap,
        borderRadius: DesignTokens.borderRadiusLarge,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minHeight: DesignTokens.minTouchTarget,
          ),
          child: isLoading
              ? const Padding(
                  padding: DesignTokens.paddingSmall,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TbShimmer(width: 64, height: 14),
                      SizedBox(height: DesignTokens.spacing8),
                      TbShimmer(width: 48, height: 24),
                    ],
                  ),
                )
              : TbMetricPill(
                  icon: icon,
                  label: label,
                  value: value,
                  unit: unit,
                  accentColor: accentColor,
                ),
        ),
      ),
    );
  }
}

/// Home dashboard summary inside a [TbSectionCard]: title, star and metric pills.
class _HomeSpotlight extends StatelessWidget {
  const _HomeSpotlight({
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
    final metrics = dashboard.metrics.entries.take(4).toList(growable: false);

    return Semantics(
      button: true,
      label: 'Home dashboard ${dashboard.title}',
      child: TbPressScale(
        onTap: onOpen,
        borderRadius: DesignTokens.borderRadiusLarge,
        child: ColoredBox(
          key: Key('home-spotlight-${dashboard.id}'),
          color: Colors.transparent,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Hero(
                    tag: 'dashboard-${dashboard.id}',
                    child: TbIcon(
                      TbIconKind.dashboardTile,
                      size: DesignTokens.iconMedium,
                      color: scheme.primary,
                    ),
                  ),
                  const SizedBox(width: DesignTokens.spacing12),
                  Expanded(
                    child: Text(
                      dashboard.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: scheme.onSurface,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  _StarButton(
                    buttonKey: Key('home-spotlight-star-${dashboard.id}'),
                    starred: dashboard.isStarred,
                    onPressed: onToggleStar,
                  ),
                ],
              ),
              if (metrics.isNotEmpty) ...[
                const SizedBox(height: DesignTokens.spacing8),
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

class _DashboardRow extends StatelessWidget {
  const _DashboardRow({
    required this.dashboard,
    required this.onOpen,
    required this.onToggleStar,
  });

  final TbDashboardInfo dashboard;
  final VoidCallback onOpen;
  final VoidCallback onToggleStar;

  @override
  Widget build(BuildContext context) {
    final firstMetric = dashboard.metrics.entries.firstOrNull;

    return TbListRow(
      key: Key('home-card-${dashboard.id}'),
      leading: TbIcon(
        TbIconKind.dashboardTile,
        size: DesignTokens.iconSmall,
        color: Theme.of(context).colorScheme.primary,
      ),
      title: dashboard.title,
      meta: firstMetric == null
          ? null
          : '${firstMetric.key} ${firstMetric.value}',
      trailing: _StarButton(
        buttonKey: Key('home-star-${dashboard.id}'),
        starred: dashboard.isStarred,
        onPressed: onToggleStar,
      ),
      onTap: onOpen,
    );
  }
}

class _StarButton extends StatelessWidget {
  const _StarButton({
    required this.buttonKey,
    required this.starred,
    required this.onPressed,
  });

  final Key buttonKey;
  final bool starred;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return IconButton(
      key: buttonKey,
      tooltip: starred ? 'Unstar' : 'Star',
      padding: DesignTokens.paddingZero,
      constraints: const BoxConstraints(
        minWidth: DesignTokens.minTouchTarget,
        minHeight: DesignTokens.minTouchTarget,
      ),
      icon: Icon(
        starred ? Icons.star_rounded : Icons.star_outline_rounded,
        color: starred ? scheme.tertiary : scheme.onSurfaceVariant,
      ),
      onPressed: onPressed,
    );
  }
}
