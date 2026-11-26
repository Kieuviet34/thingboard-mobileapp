import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:thingsboard_democloud_app/config/routes/router.dart';
import 'package:thingsboard_democloud_app/config/themes/design_tokens.dart';
import 'package:thingsboard_democloud_app/config/themes/tb_status_colors.dart';
import 'package:thingsboard_democloud_app/config/themes/tb_text_styles.dart';
import 'package:thingsboard_democloud_app/core/api/controllers/device_controller.dart';
import 'package:thingsboard_democloud_app/core/models/device_models.dart';
import 'package:thingsboard_democloud_app/core/models/tb_failure.dart';
import 'package:thingsboard_democloud_app/widgets/icons/tb_icons.dart';
import 'package:thingsboard_democloud_app/widgets/tb_app_bar.dart';
import 'package:thingsboard_democloud_app/widgets/tb_empty_state.dart';
import 'package:thingsboard_democloud_app/widgets/tb_motion.dart';
import 'package:thingsboard_democloud_app/widgets/tb_section_card.dart';
import 'package:thingsboard_democloud_app/widgets/tb_shimmer.dart';

/// Material 3 Device Profiles hub with synced "All devices" summary tile
/// and adaptive 2-column profile cards using custom [TbIcon] glyphs.
class DevicesMainPage extends ConsumerWidget {
  const DevicesMainPage({super.key});

  void _openDeviceList(
    BuildContext context, {
    String? profileId,
    String? title,
    bool? active,
    bool search = false,
  }) {
    final router = GoRouter.maybeOf(context);
    if (router == null) return;
    final params = <String, String>{
      if (profileId != null && profileId.isNotEmpty) 'profileId': profileId,
      if (title != null && title.isNotEmpty) 'title': title,
      if (active != null) 'active': active.toString(),
      if (search) 'search': 'true',
    };
    final uri = Uri(
      path: AppRoutes.deviceList,
      queryParameters: params.isEmpty ? null : params,
    );
    router.push(uri.toString());
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profilesAsync = ref.watch(deviceProfilesListProvider);
    final width = MediaQuery.sizeOf(context).width;
    final textScale = MediaQuery.textScalerOf(context).scale(1.0);
    final crossAxisCount = width >= DesignTokens.mediumMaxWidth
        ? 4
        : width >= DesignTokens.compactMaxWidth
        ? 3
        : 2;
    final cardExtent = 160.0 + ((textScale - 1.0).clamp(0.0, 1.5) * 68.0);

    return Scaffold(
      appBar: TbAppBar(
        canGoBack: false,
        title: const Text('Devices'),
        actions: [
          IconButton(
            key: const Key('devices-main-search-button'),
            tooltip: 'Search devices',
            constraints: const BoxConstraints(
              minWidth: DesignTokens.minTouchTarget,
              minHeight: DesignTokens.minTouchTarget,
            ),
            icon: const Icon(Icons.search),
            onPressed: () => _openDeviceList(context, search: true),
          ),
          IconButton(
            key: const Key('devices-main-qr-button'),
            tooltip: 'Scan QR to claim device',
            constraints: const BoxConstraints(
              minWidth: DesignTokens.minTouchTarget,
              minHeight: DesignTokens.minTouchTarget,
            ),
            icon: const TbIcon(TbIconKind.qrFrame),
            onPressed: () => GoRouter.maybeOf(context)?.push(AppRoutes.qrScan),
          ),
        ],
      ),
      body: profilesAsync.when(
        loading: () => const SingleChildScrollView(
          padding: DesignTokens.paddingMedium,
          child: TbShimmerList(itemCount: 4),
        ),
        error: (err, _) => TbEmptyState(
          icon: TbIconKind.severityCritical,
          title: 'Failed to load devices',
          subtitle: err is TbFailure ? err.message : err.toString(),
          isError: true,
          actionLabel: 'Retry',
          onAction: () =>
              ref.read(deviceProfilesListProvider.notifier).refresh(),
        ),
        data: (paged) {
          if (paged.items.isEmpty) {
            return TbEmptyState(
              icon: TbIconKind.navDevices,
              title: 'No device profiles',
              subtitle: 'Claim or add a device to get started',
              actionLabel: 'Refresh',
              onAction: () =>
                  ref.read(deviceProfilesListProvider.notifier).refresh(),
            );
          }

          final activeTotal = paged.items.fold<int>(
            0,
            (sum, p) => sum + p.activeCount,
          );
          final inactiveTotal = paged.items.fold<int>(
            0,
            (sum, p) => sum + p.inactiveCount,
          );

          return RefreshIndicator(
            onRefresh: () =>
                ref.read(deviceProfilesListProvider.notifier).refresh(),
            child: CustomScrollView(
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(
                    DesignTokens.spacing16,
                    DesignTokens.spacing12,
                    DesignTokens.spacing16,
                    DesignTokens.spacing12,
                  ),
                  sliver: SliverToBoxAdapter(
                    child: _AllDevicesSummaryTile(
                      activeCount: activeTotal,
                      inactiveCount: inactiveTotal,
                      onOpenAll: () => _openDeviceList(context),
                      onOpenOnline: () =>
                          _openDeviceList(context, active: true),
                      onOpenOffline: () =>
                          _openDeviceList(context, active: false),
                    ),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(
                    DesignTokens.spacing16,
                    0,
                    DesignTokens.spacing16,
                    84.0,
                  ),
                  sliver: SliverGrid.builder(
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: crossAxisCount,
                      mainAxisSpacing: DesignTokens.spacing12,
                      crossAxisSpacing: DesignTokens.spacing12,
                      mainAxisExtent: cardExtent,
                    ),
                    itemCount: paged.items.length,
                    itemBuilder: (context, index) {
                      final profile = paged.items[index];
                      return TbStaggeredEntry(
                        index: index,
                        child: _DeviceProfileCard(
                          profile: profile,
                          onTap: () => _openDeviceList(
                            context,
                            profileId: profile.id,
                            title: profile.name,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _AllDevicesSummaryTile extends StatelessWidget {
  const _AllDevicesSummaryTile({
    required this.activeCount,
    required this.inactiveCount,
    required this.onOpenAll,
    required this.onOpenOnline,
    required this.onOpenOffline,
  });

  final int activeCount;
  final int inactiveCount;
  final VoidCallback onOpenAll;
  final VoidCallback onOpenOnline;
  final VoidCallback onOpenOffline;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final statusColors = TbStatusColors.of(context);
    final total = activeCount + inactiveCount;

    return TbPressScale(
      onTap: onOpenAll,
      child: KeyedSubtree(
        key: const Key('all-devices-summary-card'),
        child: TbSectionCard(
          title: 'All devices',
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '$total total',
                style: TbTextStyles.tabular(
                  textTheme.bodySmall ?? TbTextStyles.bodySmall,
                ).copyWith(color: scheme.onSurfaceVariant),
              ),
              Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
            ],
          ),
          child: Wrap(
            spacing: DesignTokens.spacing8,
            runSpacing: DesignTokens.spacing8,
            children: [
              _CountFilterButton(
                key: const Key('all-devices-online-pill'),
                icon: TbIconKind.livePulse,
                label: '$activeCount Online',
                bg: statusColors.onlineContainer,
                fg: statusColors.onOnlineContainer,
                accent: statusColors.online,
                onTap: onOpenOnline,
              ),
              _CountFilterButton(
                key: const Key('all-devices-offline-pill'),
                icon: TbIconKind.offlineNode,
                label: '$inactiveCount Offline',
                bg: statusColors.offlineContainer,
                fg: statusColors.onOfflineContainer,
                accent: statusColors.offline,
                onTap: onOpenOffline,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CountFilterButton extends StatelessWidget {
  const _CountFilterButton({
    super.key,
    required this.icon,
    required this.label,
    required this.bg,
    required this.fg,
    required this.accent,
    required this.onTap,
  });

  final TbIconKind icon;
  final String label;
  final Color bg;
  final Color fg;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Semantics(
      button: true,
      label: label,
      child: Material(
        color: bg,
        borderRadius: DesignTokens.borderRadiusRound,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minWidth: DesignTokens.minTouchTarget,
              minHeight: DesignTokens.minTouchTarget,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: DesignTokens.spacing12,
                vertical: DesignTokens.spacing8,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TbIcon(icon, size: DesignTokens.iconSmall, color: accent),
                  const SizedBox(width: DesignTokens.spacing8),
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TbTextStyles.tabular(
                        textTheme.labelMedium ?? TbTextStyles.labelMedium,
                      ).copyWith(color: fg, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DeviceProfileCard extends StatelessWidget {
  const _DeviceProfileCard({required this.profile, required this.onTap});

  final TbDeviceProfileSummary profile;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final statusColors = TbStatusColors.of(context);
    final kind = TbIcons.kindForDeviceType(profile.name);

    return Material(
      key: Key('device-profile-card-${profile.id}'),
      color: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: DesignTokens.borderRadiusLarge,
        side: BorderSide(color: scheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: TbPressScale(
        onTap: onTap,
        child: Padding(
          padding: DesignTokens.cardPadding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: scheme.secondaryContainer,
                      borderRadius: DesignTokens.borderRadiusMedium,
                    ),
                    alignment: Alignment.center,
                    child: TbIcon(
                      kind,
                      size: DesignTokens.iconMedium,
                      color: scheme.onSecondaryContainer,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${profile.activeCount + profile.inactiveCount}',
                    style:
                        TbTextStyles.tabular(
                          textTheme.titleMedium ?? TbTextStyles.titleMedium,
                        ).copyWith(
                          fontWeight: FontWeight.w700,
                          color: scheme.onSurface,
                        ),
                  ),
                ],
              ),
              Text(
                profile.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: scheme.onSurface,
                ),
              ),
              Wrap(
                spacing: DesignTokens.spacing8,
                runSpacing: DesignTokens.spacing4,
                children: [
                  _MiniStatusCount(
                    icon: TbIconKind.livePulse,
                    count: profile.activeCount,
                    color: statusColors.online,
                    bg: statusColors.onlineContainer,
                    fg: statusColors.onOnlineContainer,
                    semanticPrefix: 'online',
                  ),
                  _MiniStatusCount(
                    icon: TbIconKind.offlineNode,
                    count: profile.inactiveCount,
                    color: statusColors.offline,
                    bg: statusColors.offlineContainer,
                    fg: statusColors.onOfflineContainer,
                    semanticPrefix: 'offline',
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MiniStatusCount extends StatelessWidget {
  const _MiniStatusCount({
    required this.icon,
    required this.count,
    required this.color,
    required this.bg,
    required this.fg,
    required this.semanticPrefix,
  });

  final TbIconKind icon;
  final int count;
  final Color color;
  final Color bg;
  final Color fg;
  final String semanticPrefix;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Semantics(
      label: '$count $semanticPrefix',
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: DesignTokens.spacing8,
          vertical: DesignTokens.spacing4,
        ),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: DesignTokens.borderRadiusRound,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            TbIcon(icon, size: DesignTokens.iconXs, color: color),
            const SizedBox(width: DesignTokens.spacing4),
            Text(
              '$count',
              style: TbTextStyles.tabular(
                textTheme.labelSmall ?? TbTextStyles.labelSmall,
              ).copyWith(color: fg, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }
}
