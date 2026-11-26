import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:thingsboard_democloud_app/config/routes/router.dart';
import 'package:thingsboard_democloud_app/config/themes/design_tokens.dart';
import 'package:thingsboard_democloud_app/config/themes/tb_text_styles.dart';
import 'package:thingsboard_democloud_app/core/api/controllers/auth_controller.dart';
import 'package:thingsboard_democloud_app/core/api/controllers/notification_controller.dart';
import 'package:thingsboard_democloud_app/core/api/controllers/server_config_controller.dart';
import 'package:thingsboard_democloud_app/core/api/controllers/tenant_controller.dart';
import 'package:thingsboard_democloud_app/core/models/auth_models.dart';
import 'package:thingsboard_democloud_app/core/models/entity_id.dart';
import 'package:thingsboard_democloud_app/widgets/icons/tb_icons.dart';
import 'package:thingsboard_democloud_app/widgets/tb_app_bar.dart';
import 'package:thingsboard_democloud_app/widgets/tb_list_row.dart';
import 'package:thingsboard_democloud_app/widgets/tb_motion.dart';
import 'package:thingsboard_democloud_app/widgets/tb_section_card.dart';
import 'package:thingsboard_democloud_app/widgets/tb_status_badge.dart';

/// More hub screen with user header, RBAC-aware entity shortcuts, unread badge, and logout.
class MorePage extends ConsumerWidget {
  const MorePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final authAsync = ref.watch(authProvider);
    final serverConfig = ref.watch(serverConfigProvider);
    final unreadAsync = ref.watch(unreadNotificationsCountProvider);

    final authenticated = authAsync.valueOrNull is AuthAuthenticated
        ? authAsync.valueOrNull! as AuthAuthenticated
        : null;
    final user = authenticated?.user;
    final mode = authenticated?.mode ?? serverConfig.mode;
    final authority = user?.authority ?? Authority.unknown;
    final showTenant = canAccessTenantWorkspace(authority);
    final showCustomers = authority != Authority.customerUser;
    final unreadCount = unreadAsync.valueOrNull ?? 0;

    return Scaffold(
      appBar: TbAppBar(canGoBack: false, title: const Text('More')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: DesignTokens.maxReadableWidth,
            ),
            child: SingleChildScrollView(
              padding: DesignTokens.paddingMedium,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TbStaggeredEntry(
                    index: 0,
                    child: _UserHeaderCard(
                      initials: user?.initials ?? 'TB',
                      displayName: user?.displayName ?? 'ThingsBoard User',
                      email: user?.email ?? '',
                      roleLabel: _shortRoleLabel(authority),
                      mode: mode,
                      hostLabel: _hostFromUrl(serverConfig.baseUrl),
                      onTap: () => _navigate(context, AppRoutes.profile),
                    ),
                  ),
                  const SizedBox(height: DesignTokens.spacing20),
                  TbStaggeredEntry(
                    index: 1,
                    child: TbSectionCard(
                      title: 'Entities',
                      child: Column(
                        children: [
                          if (showTenant)
                            _MoreRow(
                              icon: TbIconKind.gateway,
                              title: authority == Authority.sysAdmin
                                  ? 'Tenants'
                                  : 'Tenant',
                              meta: authority == Authority.sysAdmin
                                  ? 'Tenants & profiles'
                                  : 'Workspace, views & edges',
                              onTap: () => _navigate(context, AppRoutes.tenant),
                            ),
                          if (showCustomers)
                            _MoreRow(
                              icon: TbIconKind.customerOrg,
                              title: 'Customers',
                              meta: 'Organizations & contacts',
                              onTap: () =>
                                  _navigate(context, AppRoutes.customers),
                            ),
                          _MoreRow(
                            icon: TbIconKind.assetBuilding,
                            title: 'Assets',
                            meta: 'Sites, telemetry & relations',
                            onTap: () => _navigate(context, AppRoutes.assets),
                          ),
                          _MoreRow(
                            icon: TbIconKind.auditLog,
                            title: 'Audit Logs',
                            meta: 'Activity timeline',
                            onTap: () =>
                                _navigate(context, AppRoutes.auditLogs),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: DesignTokens.spacing16),
                  TbStaggeredEntry(
                    index: 2,
                    child: TbSectionCard(
                      title: 'Account',
                      child: Column(
                        children: [
                          _MoreRow(
                            icon: TbIconKind.notificationInbox,
                            title: 'Notifications',
                            meta: unreadCount > 0
                                ? '$unreadCount unread'
                                : 'Inbox & alerts',
                            badge: unreadCount > 0
                                ? _UnreadCountPill(count: unreadCount)
                                : null,
                            onTap: () =>
                                _navigate(context, AppRoutes.notifications),
                          ),
                          _MoreRow(
                            materialIcon: Icons.tune_rounded,
                            title: 'Profile & Settings',
                            meta: 'Theme, password & server',
                            onTap: () => _navigate(context, AppRoutes.profile),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: DesignTokens.spacing24),
                  TbStaggeredEntry(
                    index: 3,
                    child: Semantics(
                      button: true,
                      label: 'Log out',
                      child: OutlinedButton.icon(
                        key: const Key('more_logout_button'),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(
                            double.infinity,
                            DesignTokens.minTouchTarget,
                          ),
                          foregroundColor: scheme.error,
                          side: BorderSide(color: scheme.error),
                        ),
                        icon: const Icon(Icons.logout_rounded),
                        label: const Text('Log out'),
                        onPressed: () => _confirmLogout(context, ref),
                      ),
                    ),
                  ),
                  const SizedBox(height: 84),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _navigate(BuildContext context, String route) {
    final router = GoRouter.maybeOf(context);
    if (router != null) {
      context.push(route);
    }
  }

  Future<void> _confirmLogout(BuildContext context, WidgetRef ref) async {
    final scheme = Theme.of(context).colorScheme;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Log out?'),
          content: const Text('End the active ThingsBoard session.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: scheme.error,
                foregroundColor: scheme.onError,
              ),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Log out'),
            ),
          ],
        );
      },
    );
    if (confirmed == true) {
      await ref.read(authProvider.notifier).logout();
    }
  }

  static String _shortRoleLabel(Authority authority) => switch (authority) {
    Authority.sysAdmin => 'Sys Admin',
    Authority.tenantAdmin => 'Tenant Admin',
    Authority.customerUser => 'Customer',
    Authority.billingAdmin => 'Billing Admin',
    _ => 'User',
  };

  static String _hostFromUrl(String url) {
    final parsed = Uri.tryParse(url);
    if (parsed != null && parsed.host.isNotEmpty) {
      return parsed.host;
    }
    return url;
  }
}

class _UserHeaderCard extends StatelessWidget {
  const _UserHeaderCard({
    required this.initials,
    required this.displayName,
    required this.email,
    required this.roleLabel,
    required this.mode,
    required this.hostLabel,
    required this.onTap,
  });

  final String initials;
  final String displayName;
  final String email;
  final String roleLabel;
  final SessionMode mode;
  final String hostLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Semantics(
      button: true,
      label: 'Profile $displayName',
      child: Material(
        color: scheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: DesignTokens.borderRadiusXl,
          side: BorderSide(color: scheme.outlineVariant),
        ),
        child: TbPressScale(
          borderRadius: DesignTokens.borderRadiusXl,
          onTap: onTap,
          child: Padding(
            padding: DesignTokens.cardPadding,
            child: Row(
              children: [
                CircleAvatar(
                  radius: 24,
                  backgroundColor: scheme.primaryContainer,
                  foregroundColor: scheme.onPrimaryContainer,
                  child: Text(
                    initials,
                    style: textTheme.titleMedium?.copyWith(
                      color: scheme.onPrimaryContainer,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: DesignTokens.spacing12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.titleMedium?.copyWith(
                          color: scheme.onSurface,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (email.isNotEmpty) ...[
                        const SizedBox(height: DesignTokens.spacing2),
                        Text(
                          email,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                      const SizedBox(height: DesignTokens.spacing8),
                      Wrap(
                        spacing: DesignTokens.spacing8,
                        runSpacing: DesignTokens.spacing4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          if (mode == SessionMode.demo)
                            TbStatusBadge.demo(compact: true)
                          else
                            const TbStatusBadge(
                              label: 'LIVE',
                              icon: TbIconKind.livePulse,
                              tone: TbStatusTone.online,
                              compact: true,
                            ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: DesignTokens.spacing8,
                              vertical: DesignTokens.spacing2,
                            ),
                            decoration: BoxDecoration(
                              color: scheme.surfaceContainerHigh,
                              borderRadius: DesignTokens.borderRadiusRound,
                            ),
                            child: Text(
                              roleLabel,
                              style: textTheme.labelSmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          if (mode == SessionMode.live && hostLabel.isNotEmpty)
                            Text(
                              hostLabel,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: textTheme.labelSmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: DesignTokens.spacing8),
                Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Navigation row inside a [TbSectionCard]: icon, title, one meta line, chevron.
class _MoreRow extends StatelessWidget {
  const _MoreRow({
    this.icon,
    this.materialIcon,
    required this.title,
    required this.meta,
    required this.onTap,
    this.badge,
  });

  final TbIconKind? icon;
  final IconData? materialIcon;
  final String title;
  final String meta;
  final VoidCallback onTap;
  final Widget? badge;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return TbListRow(
      leading: icon != null
          ? TbIcon(icon!, color: scheme.primary)
          : Icon(
              materialIcon,
              size: DesignTokens.iconMedium,
              color: scheme.primary,
            ),
      title: title,
      meta: meta,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (badge != null) ...[
            badge!,
            const SizedBox(width: DesignTokens.spacing4),
          ],
          Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
        ],
      ),
      onTap: onTap,
    );
  }
}

class _UnreadCountPill extends StatelessWidget {
  const _UnreadCountPill({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final label = count > 99 ? '99+' : '$count';

    return Semantics(
      label: '$count unread notifications',
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: DesignTokens.spacing8,
          vertical: DesignTokens.spacing2,
        ),
        decoration: BoxDecoration(
          color: scheme.errorContainer,
          borderRadius: DesignTokens.borderRadiusRound,
        ),
        child: Text(
          label,
          style:
              TbTextStyles.tabular(
                textTheme.labelSmall ?? TbTextStyles.labelSmall,
              ).copyWith(
                color: scheme.onErrorContainer,
                fontWeight: FontWeight.w700,
              ),
        ),
      ),
    );
  }
}
