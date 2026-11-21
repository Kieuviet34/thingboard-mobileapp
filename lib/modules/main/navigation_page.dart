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
import 'package:thingsboard_democloud_app/widgets/nav/tb_floating_nav_bar.dart';

/// Adaptive navigation shell:
/// - `< 600dp`: floating glass [TbFloatingNavBar] (label slides in beside icon)
/// - `>= 600dp`: side [NavigationRail] (extended on large, tall windows)
class NavigationPage extends ConsumerWidget {
  const NavigationPage({super.key, this.navigationShell, this.child});

  final StatefulNavigationShell? navigationShell;
  final Widget? child;

  static const List<TbMainNavigationItem> destinations = [
    TbMainNavigationItem(
      title: 'Home',
      tbIconKind: TbIconKind.navHome,
      path: '/home',
    ),
    TbMainNavigationItem(
      title: 'Alarms',
      tbIconKind: TbIconKind.navAlarms,
      path: '/alarms',
      badgeSemantics: 'active',
    ),
    TbMainNavigationItem(
      title: 'Devices',
      tbIconKind: TbIconKind.navDevices,
      path: '/devices',
    ),
    TbMainNavigationItem(
      title: 'More',
      tbIconKind: TbIconKind.navMore,
      path: '/more',
      badgeSemantics: 'unread',
    ),
  ];

  int _indexForLocation(String location) {
    if (location.startsWith('/alarms')) return 1;
    if (location.startsWith('/devices')) return 2;
    if (location.startsWith('/more') ||
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

  Widget _railIcon(
    BuildContext context,
    int index, {
    required bool filled,
    required int badgeCount,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final item = destinations[index];
    final icon = TbIcon(
      item.tbIconKind,
      size: DesignTokens.iconMedium,
      filled: filled,
      semanticLabel: badgeCount > 0
          ? '${item.title}, $badgeCount ${item.badgeSemantics}'.trim()
          : item.title,
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
    final size = MediaQuery.sizeOf(context);
    final width = size.width;
    final useRail = width >= DesignTokens.compactMaxWidth;
    // Landscape phones are wide but short: keep the rail slim so data keeps
    // the width, and expand it only on genuinely large windows.
    final extendedRail =
        width >= DesignTokens.mediumMaxWidth &&
        size.height >= DesignTokens.compactMinHeight;
    final floatingEdge = width < DesignTokens.smallPhoneMaxWidth
        ? DesignTokens.spacing8
        : DesignTokens.spacing16;
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
                    child: _ScrollableRail(
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
                              icon: _railIcon(
                                context,
                                i,
                                filled: false,
                                badgeCount: badgeCounts[i],
                              ),
                              selectedIcon: _railIcon(
                                context,
                                i,
                                filled: true,
                                badgeCount: badgeCounts[i],
                              ),
                              label: Text(destinations[i].title),
                            ),
                        ],
                      ),
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
                  padding: EdgeInsets.fromLTRB(
                    floatingEdge,
                    0,
                    floatingEdge,
                    DesignTokens.spacing12,
                  ),
                  child: Center(
                    heightFactor: 1,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        maxWidth: DesignTokens.floatingNavMaxWidth,
                      ),
                      child: TbFloatingNavBar(
                        selectedIndex: currentIndex,
                        onSelected: (idx) =>
                            _selectIndex(context, idx, currentIndex),
                        destinations: [
                          for (var i = 0; i < destinations.length; i++)
                            TbNavDestination(
                              label: destinations[i].title,
                              icon: destinations[i].tbIconKind,
                              badgeCount: badgeCounts[i],
                              badgeSemantics: destinations[i].badgeSemantics,
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
      ),
    );
  }
}

/// Keeps [NavigationRail] fully reachable on short windows (landscape phones,
/// split-screen) by scrolling instead of overflowing.
class _ScrollableRail extends StatelessWidget {
  const _ScrollableRail({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: IntrinsicHeight(child: child),
        ),
      ),
    );
  }
}
