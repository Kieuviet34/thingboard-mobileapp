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
import 'package:thingsboard_democloud_app/widgets/tb_motion.dart';
import 'package:thingsboard_democloud_app/widgets/tb_status_badge.dart';

/// More hub screen with user header, RBAC-aware entity shortcuts, unread badge, and logout.
class MorePage extends ConsumerWidget {
  const MorePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
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
                  Padding(
                    padding: const EdgeInsets.only(
                      left: DesignTokens.spacing4,
                      bottom: DesignTokens.spacing8,
                    ),
                    child: Text(
                      'Entities',
                      style: textTheme.labelLarge?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  TbStaggeredEntry(
                    index: 1,
                    child: _GroupedSection(
                      children: [
                        if (showTenant)
                          _MoreTile(
                            leading: TbIcon(
                              TbIconKind.gateway,
                              color: scheme.primary,
                            ),
                            title: authority == Authority.sysAdmin
                                ? 'Tenants'
                                : 'Tenant',
                            subtitle: authority == Authority.sysAdmin
                                ? 'Tenants & profiles'
                                : 'Workspace, views & edges',
                            onTap: () => _navigate(context, AppRoutes.tenant),
                          ),
                        if (showCustomers)
                          _MoreTile(
                            leading: TbIcon(
                              TbIconKind.customerOrg,
                              color: scheme.primary,
                            ),
                            title: 'Customers',
                            subtitle: 'Organizations & contacts',
                            onTap: () =>
                                _navigate(context, AppRoutes.customers),
                          ),
                        _MoreTile(
                          leading: TbIcon(
                            TbIconKind.assetBuilding,
                            color: scheme.primary,
                          ),
                          title: 'Assets',
                          subtitle: 'Sites, telemetry & relations',
                          onTap: () => _navigate(context, AppRoutes.assets),
                        ),
                        _MoreTile(
                          leading: TbIcon(
                            TbIconKind.auditLog,
                            color: scheme.primary,
                          ),
                          title: 'Audit Logs',
                          subtitle: 'Activity timeline',
                          onTap: () => _navigate(context, AppRoutes.auditLogs),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: DesignTokens.spacing20),
                  Padding(
                    padding: const EdgeInsets.only(
                      left: DesignTokens.spacing4,
                      bottom: DesignTokens.spacing8,
                    ),
                    child: Text(
                      'Account',
                      style: textTheme.labelLarge?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  TbStaggeredEntry(
                    index: 2,
                    child: _GroupedSection(
                      children: [
                        _MoreTile(
                          leading: TbIcon(
                            TbIconKind.notificationInbox,
                            color: scheme.primary,
                          ),
                          title: 'Notifications',
                          subtitle: unreadCount > 0
                              ? '$unreadCount unread'
                              : 'Inbox & alerts',
                          trailingBadge: unreadCount > 0
                              ? _UnreadCountPill(count: unreadCount)
                              : null,
                          onTap: () =>
                              _navigate(context, AppRoutes.notifications),
                        ),
                        _MoreTile(
                          leading: Icon(
                            Icons.tune_rounded,
                            size: DesignTokens.iconMedium,
                            color: scheme.primary,
                          ),
                          title: 'Profile & Settings',
                          subtitle: 'Theme, password & server',
                          onTap: () => _navigate(context, AppRoutes.profile),
                        ),
                      ],
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

class _GroupedSection extends StatelessWidget {
  const _GroupedSection({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: DesignTokens.borderRadiusLarge,
        side: BorderSide(color: scheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < children.length; i++) ...[
            children[i],
            if (i < children.length - 1)
              Divider(
                height: 1,
                thickness: 1,
                indent: 56,
                color: scheme.outlineVariant,
              ),
          ],
        ],
      ),
    );
  }
}

class _MoreTile extends StatelessWidget {
  const _MoreTile({
    required this.leading,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.trailingBadge,
  });

  final Widget leading;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final Widget? trailingBadge;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Semantics(
      button: true,
      label: title,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minHeight: DesignTokens.minTouchTarget,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: DesignTokens.spacing16,
              vertical: DesignTokens.spacing12,
            ),
            child: Row(
              children: [
                SizedBox(
                  width: DesignTokens.iconLarge,
                  child: Center(child: leading),
                ),
                const SizedBox(width: DesignTokens.spacing12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.bodyLarge?.copyWith(
                          color: scheme.onSurface,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                if (trailingBadge != null) ...[
                  const SizedBox(width: DesignTokens.spacing8),
                  trailingBadge!,
                ],
                const SizedBox(width: DesignTokens.spacing4),
                Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
              ],
            ),
          ),
        ),
      ),
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
