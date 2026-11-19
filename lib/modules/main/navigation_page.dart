import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:thingsboard_democloud_app/modules/main/model/main_navigation_item.dart';
import 'package:thingsboard_democloud_app/modules/main/widgets/tb_navigation_bar_widget.dart';

class NavigationPage extends ConsumerWidget {
  const NavigationPage({super.key, required this.child});
  final Widget child;

  static const List<TbMainNavigationItem> _bottomItems = [
    TbMainNavigationItem(title: 'Home', icon: Icons.home, path: '/home'),
    TbMainNavigationItem(
      title: 'Alarms',
      icon: Icons.notifications_active_outlined,
      path: '/alarms',
    ),
    TbMainNavigationItem(
      title: 'Devices',
      icon: Icons.devices_other,
      path: '/devices',
    ),
    TbMainNavigationItem(
      title: 'More',
      icon: Icons.menu_outlined,
      path: '/more',
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final location = GoRouterState.of(context).uri.toString();
    final currentIndex = _indexForLocation(location);

    return Scaffold(
      body: child,
      bottomNavigationBar: TbNavigationBarWidget(
        currentIndex: currentIndex,
        onTap: (index) {
          if (index == currentIndex) return;
          context.go(_bottomItems[index].path);
        },
        customBottomBarItems: _bottomItems,
      ),
    );
  }
}
