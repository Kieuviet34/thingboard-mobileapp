import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:thingsboard_democloud_app/config/themes/design_tokens.dart';
import 'package:thingsboard_democloud_app/core/api/controllers/alarm_controller.dart';
import 'package:thingsboard_democloud_app/core/api/controllers/notification_controller.dart';
import 'package:thingsboard_democloud_app/core/api/controllers/server_config_controller.dart';
import 'package:thingsboard_democloud_app/core/models/auth_models.dart';
import 'package:thingsboard_democloud_app/modules/main/model/main_navigation_item.dart';
import 'package:thingsboard_democloud_app/widgets/icons/tb_icons.dart';

/// Adaptive Material 3 navigation shell:
/// - `< 600dp`: bottom [NavigationBar]
/// - `>= 600dp`: side [NavigationRail] (extended on `>= 840dp`)
class NavigationPage extends ConsumerWidget {
  const NavigationPage({super.key, this.navigationShell, this.child});

  final StatefulNavigationShell? navigationShell;
  final Widget? child;

  static const List<TbMainNavigationItem> destinations = [
    TbMainNavigationItem(
      title: 'Home',
      icon: Icons.home_outlined,
      tbIconKind: TbIconKind.navHome,
      path: '/home',
    ),
    TbMainNavigationItem(
      title: 'Alarms',
      icon: Icons.notifications_active_outlined,
      tbIconKind: TbIconKind.navAlarms,
      path: '/alarms',
    ),
    TbMainNavigationItem(
      title: 'Devices',
      icon: Icons.devices_other_outlined,
      tbIconKind: TbIconKind.navDevices,
      path: '/devices',
    ),
    TbMainNavigationItem(
      title: 'More',
      icon: Icons.grid_view_outlined,
      tbIconKind: TbIconKind.navMore,
      path: '/more',
    ),
  ];

  int _indexForLocation(String location) {
    if (location.startsWith('/alarms')) return 1;
    if (location.startsWith('/devices')) return 2;
    if (location.startsWith('/more') ||
        location.startsWith('/tenant') ||
        location.startsWith('/customers') ||
        location.startsWith('/assets') ||
        location.startsWith('/auditLogs') ||
        location.startsWith('/notifications') ||
        location.startsWith('/profile')) {
      return 3;
    }
    return 0;
  }

  void _selectIndex(BuildContext context, int index, int currentIndex) {
    final shell = navigationShell;
    if (shell != null) {
      shell.goBranch(index, initialLocation: index == shell.currentIndex);
      return;
    }
    if (index == currentIndex) return;
    final router = GoRouter.maybeOf(context);
    router?.go(destinations[index].path);
  }

  Widget _badgedIcon(
    BuildContext context, {
    required TbIconKind kind,
    required bool filled,
    required int badgeCount,
    required String semanticLabel,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final icon = TbIcon(
      kind,
      size: DesignTokens.iconMedium,
      filled: filled,
      semanticLabel: badgeCount > 0
          ? '$semanticLabel, $badgeCount unread'
          : semanticLabel,
    );
    if (badgeCount <= 0) return icon;
    return Badge.count(
      count: badgeCount,
      backgroundColor: scheme.error,
      textColor: scheme.onError,
      child: icon,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final routerState = GoRouter.maybeOf(context);
    final location = routerState != null
        ? GoRouterState.of(context).uri.toString()
        : '/home';
    final currentIndex =
        navigationShell?.currentIndex ?? _indexForLocation(location);

    final mode = ref.watch(serverConfigProvider.select((s) => s.mode));
    final alarmsState = ref.watch(alarmsListProvider(null)).valueOrNull;
    final activeAlarmCount =
        alarmsState?.items.where((a) => !a.cleared).length ?? 0;
    final unreadNotifications = mode == SessionMode.demo
        ? (ref
                  .watch(notificationsListProvider(false))
                  .valueOrNull
                  ?.items
                  .where((n) => !n.isRead)
                  .length ??
              0)
        : (ref.watch(unreadNotificationsCountProvider).valueOrNull ?? 0);

    final badgeCounts = <int>[0, activeAlarmCount, 0, unreadNotifications];
    final bodyWidget = navigationShell ?? child ?? const SizedBox.shrink();
    final width = MediaQuery.sizeOf(context).width;
    final useRail = width >= DesignTokens.compactMaxWidth;
    final extendedRail = width >= DesignTokens.mediumMaxWidth;
    final scheme = Theme.of(context).colorScheme;

    return PopScope(
      canPop: currentIndex == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && currentIndex != 0) {
          _selectIndex(context, 0, currentIndex);
        }
      },
      child: Scaffold(
        extendBody: !useRail,
        body: useRail
            ? Row(
                children: [
                  SafeArea(
                    right: false,
                    child: NavigationRail(
                      selectedIndex: currentIndex,
                      extended: extendedRail,
                      labelType: extendedRail
                          ? NavigationRailLabelType.none
                          : NavigationRailLabelType.all,
                      onDestinationSelected: (idx) =>
                          _selectIndex(context, idx, currentIndex),
                      destinations: [
                        for (var i = 0; i < destinations.length; i++)
                          NavigationRailDestination(
                            icon: _badgedIcon(
                              context,
                              kind: destinations[i].tbIconKind!,
                              filled: false,
                              badgeCount: badgeCounts[i],
                              semanticLabel: destinations[i].title,
                            ),
                            selectedIcon: _badgedIcon(
                              context,
                              kind: destinations[i].tbIconKind!,
                              filled: true,
                              badgeCount: badgeCounts[i],
                              semanticLabel: destinations[i].title,
                            ),
                            label: Text(destinations[i].title),
                          ),
                      ],
                    ),
                  ),
                  VerticalDivider(
                    width: 1,
                    thickness: 1,
                    color: scheme.outlineVariant,
                  ),
                  Expanded(child: bodyWidget),
                ],
              )
            : bodyWidget,
        bottomNavigationBar: useRail
            ? null
            : SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    DesignTokens.spacing16,
                    0,
                    DesignTokens.spacing16,
                    DesignTokens.spacing12,
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(DesignTokens.spacing32),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                      child: Container(
                        decoration: BoxDecoration(
                          color: scheme.surface.withValues(alpha: 0.82),
                          borderRadius: BorderRadius.circular(
                            DesignTokens.spacing32,
                          ),
                          border: Border.all(
                            color: scheme.outlineVariant.withValues(
                              alpha: 0.45,
                            ),
                            width: 1.0,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: scheme.shadow.withValues(alpha: 0.12),
                              blurRadius: 20,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: NavigationBar(
                          backgroundColor: Colors.transparent,
                          elevation: 0,
                          height: DesignTokens.spacing64,
                          labelBehavior: NavigationDestinationLabelBehavior
                              .onlyShowSelected,
                          selectedIndex: currentIndex,
                          onDestinationSelected: (idx) =>
                              _selectIndex(context, idx, currentIndex),
                          destinations: [
                            for (var i = 0; i < destinations.length; i++)
                              NavigationDestination(
                                tooltip: destinations[i].title,
                                icon: _badgedIcon(
                                  context,
                                  kind: destinations[i].tbIconKind!,
                                  filled: false,
                                  badgeCount: badgeCounts[i],
                                  semanticLabel: destinations[i].title,
                                ),
                                selectedIcon: _badgedIcon(
                                  context,
                                  kind: destinations[i].tbIconKind!,
                                  filled: true,
                                  badgeCount: badgeCounts[i],
                                  semanticLabel: destinations[i].title,
                                ),
                                label: destinations[i].title,
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
      ),
    );
  }
}
