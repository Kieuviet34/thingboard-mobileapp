import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:thingsboard_democloud_app/config/themes/app_colors.dart';
import 'package:thingsboard_democloud_app/config/themes/tb_text_styles.dart';
import 'package:thingsboard_democloud_app/constants/app_constants.dart';
import 'package:thingsboard_democloud_app/constants/assets_path.dart';
import 'package:thingsboard_democloud_app/core/auth/login/provider/auth_provider.dart';
import 'package:thingsboard_democloud_app/widgets/tb_app_bar.dart';

class HomePlaceholderPage extends ConsumerStatefulWidget {
  const HomePlaceholderPage({super.key});

  @override
  ConsumerState<HomePlaceholderPage> createState() =>
      _HomePlaceholderPageState();
}

class _HomePlaceholderPageState extends ConsumerState<HomePlaceholderPage> {
  int _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);
    final theme = Theme.of(context);
    final endpointHost =
        Uri.tryParse(ThingsboardAppConstants.thingsBoardApiEndpoint)?.host ??
        ThingsboardAppConstants.thingsBoardApiEndpoint;

    return Scaffold(
      appBar: TbAppBar(
        canGoBack: false,
        title: Center(
          child: SizedBox(
            height: 24,
            child: SvgPicture.asset(
              ThingsboardImage.thingsBoardWithTitle,
              colorFilter: ColorFilter.mode(
                theme.primaryColor,
                BlendMode.srcIn,
              ),
            ),
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Log Out',
            icon: const Icon(Icons.logout, color: AppColors.textError),
            onPressed: () async {
              await ref.read(authProvider.notifier).logout();
              if (context.mounted) {
                context.go('/login');
              }
            },
          ),
        ],
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Card(
            elevation: 2,
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                spacing: 12,
                children: [
                  Icon(
                    Icons.cloud_done_outlined,
                    size: 48,
                    color: theme.primaryColor,
                  ),
                  Text('Signed in (UI Replica)', style: TbTextStyles.titleSmall),
                  if (authState.userEmail.isNotEmpty)
                    Text(
                      authState.userEmail,
                      style: TbTextStyles.bodyMedium.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(4),
                      color: theme.primaryColor.withValues(alpha: 0.08),
                    ),
                    padding: const EdgeInsets.symmetric(
                      vertical: 6,
                      horizontal: 12,
                    ),
                    child: Text(
                      'API Endpoint: $endpointHost',
                      style: TbTextStyles.bodySmall.copyWith(
                        color: theme.primaryColor,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: () async {
                      await ref.read(authProvider.notifier).logout();
                      if (context.mounted) {
                        context.go('/login');
                      }
                    },
                    icon: const Icon(Icons.logout, color: AppColors.textError),
                    label: Text(
                      'Log Out to Login Screen',
                      style: TbTextStyles.labelMedium.copyWith(
                        color: AppColors.textError,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: (index) => setState(() => _selectedIndex = index),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
          BottomNavigationBarItem(
            icon: Icon(Icons.notifications_active_outlined),
            label: 'Alarms',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.devices_other),
            label: 'Devices',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.menu_outlined),
            label: 'More',
          ),
        ],
      ),
    );
  }
}
