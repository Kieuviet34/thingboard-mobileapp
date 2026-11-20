import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:thingsboard_democloud_app/config/themes/design_tokens.dart';
import 'package:thingsboard_democloud_app/config/themes/tb_theme_utils.dart';
import 'package:thingsboard_democloud_app/core/api/controllers/auth_controller.dart';
import 'package:thingsboard_democloud_app/core/api/controllers/notification_controller.dart';
import 'package:thingsboard_democloud_app/core/api/controllers/server_config_controller.dart';
import 'package:thingsboard_democloud_app/core/api/controllers/user_profile_controller.dart';
import 'package:thingsboard_democloud_app/core/models/auth_models.dart';
import 'package:thingsboard_democloud_app/core/models/notification_models.dart';
import 'package:thingsboard_democloud_app/core/models/tb_failure.dart';
import 'package:thingsboard_democloud_app/core/models/user_models.dart';
import 'package:thingsboard_democloud_app/widgets/icons/tb_icons.dart';
import 'package:thingsboard_democloud_app/widgets/tb_app_bar.dart';
import 'package:thingsboard_democloud_app/widgets/tb_empty_state.dart';
import 'package:thingsboard_democloud_app/widgets/tb_motion.dart';
import 'package:thingsboard_democloud_app/widgets/tb_network_inspector_dialog.dart';
import 'package:thingsboard_democloud_app/widgets/tb_shimmer.dart';
import 'package:thingsboard_democloud_app/widgets/tb_status_badge.dart';

/// Profile & Settings hub managing user profile, password rotation, theme,
/// host endpoint / session mode switching, and notification preferences.
class ProfileSettingsPage extends ConsumerWidget {
  const ProfileSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(userProfileControllerProvider);
    final serverConfig = ref.watch(serverConfigProvider);
    final themeMode = ref.watch(themeModeProvider);
    final notifSettingsAsync = ref.watch(notificationSettingsProvider);
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: TbAppBar(
        canGoBack: true,
        title: const Text('Profile & Settings'),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: DesignTokens.maxReadableWidth,
            ),
            child: profileAsync.when(
              error: (error, _) => TbEmptyState(
                icon: TbIconKind.customerOrg,
                title: 'Failed to load profile',
                subtitle: error.toString(),
                actionLabel: 'Retry',
                onAction: () => ref.invalidate(userProfileControllerProvider),
                isError: true,
              ),
              loading: () => const SingleChildScrollView(
                padding: DesignTokens.paddingMedium,
                child: Column(
                  children: [
                    TbShimmer(height: 120),
                    SizedBox(height: DesignTokens.spacing16),
                    TbShimmerList(itemCount: 4),
                  ],
                ),
              ),
              data: (user) => SingleChildScrollView(
                padding: DesignTokens.paddingMedium,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TbStaggeredEntry(
                      index: 0,
                      child: _ProfileHeader(
                        user: user,
                        mode: serverConfig.mode,
                        onEditProfile: () =>
                            _openEditProfileSheet(context, ref, user),
                      ),
                    ),
                    const SizedBox(height: DesignTokens.spacing20),

                    // Security & Account
                    _SectionHeader(title: 'Security & Account'),
                    TbStaggeredEntry(
                      index: 1,
                      child: _SettingsGroup(
                        children: [
                          _SettingsTile(
                            icon: Icons.lock_outline_rounded,
                            title: 'Change Password',
                            subtitle: 'Update credentials with password policy',
                            onTap: () => _openChangePasswordSheet(
                              context,
                              ref,
                              serverConfig.passwordPolicy,
                            ),
                          ),
                          _SettingsTile(
                            icon: Icons.badge_outlined,
                            title: 'User Authority',
                            subtitle: user.authority.displayLabel,
                            trailing: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: DesignTokens.spacing8,
                                vertical: DesignTokens.spacing2,
                              ),
                              decoration: BoxDecoration(
                                color: scheme.surfaceContainerHigh,
                                borderRadius: DesignTokens.borderRadiusRound,
                              ),
                              child: Text(
                                user.authority.wireValue,
                                style: textTheme.labelSmall?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: DesignTokens.spacing20),

                    // Appearance
                    _SectionHeader(title: 'Appearance'),
                    TbStaggeredEntry(
                      index: 2,
                      child: Material(
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
                                'Theme Mode',
                                style: textTheme.titleSmall?.copyWith(
                                  color: scheme.onSurface,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: DesignTokens.spacing4),
                              Text(
                                'Choose light, dark, or system matching theme',
                                style: textTheme.bodySmall?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(height: DesignTokens.spacing12),
                              SegmentedButton<ThemeMode>(
                                segments: const [
                                  ButtonSegment(
                                    value: ThemeMode.system,
                                    label: Text('System'),
                                    icon: Icon(Icons.brightness_auto_rounded),
                                  ),
                                  ButtonSegment(
                                    value: ThemeMode.light,
                                    label: Text('Light'),
                                    icon: Icon(Icons.light_mode_outlined),
                                  ),
                                  ButtonSegment(
                                    value: ThemeMode.dark,
                                    label: Text('Dark'),
                                    icon: Icon(Icons.dark_mode_outlined),
                                  ),
                                ],
                                selected: {themeMode},
                                onSelectionChanged: (selected) async {
                                  final newMode = selected.first;
                                  ref
                                      .read(themeModeProvider.notifier)
                                      .setThemeMode(newMode);
                                  await ref
                                      .read(tbAppPreferencesProvider)
                                      .setThemeMode(newMode);
                                },
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: DesignTokens.spacing20),

                    // Server & Session Mode
                    _SectionHeader(title: 'Server & Connectivity'),
                    TbStaggeredEntry(
                      index: 3,
                      child: _SettingsGroup(
                        children: [
                          _SettingsTile(
                            icon: Icons.dns_outlined,
                            title: 'ThingsBoard Server',
                            subtitle: serverConfig.baseUrl,
                            onTap: () => _openServerDialog(
                              context,
                              ref,
                              serverConfig.baseUrl,
                            ),
                          ),
                          _SettingsTile(
                            icon: serverConfig.mode == SessionMode.demo
                                ? Icons.science_outlined
                                : Icons.cloud_done_outlined,
                            title: 'Session Mode',
                            subtitle: serverConfig.mode == SessionMode.demo
                                ? 'Demo Mode (Offline Mock Data)'
                                : 'Live Mode (Connected to Server)',
                            trailing: Switch(
                              value: serverConfig.mode == SessionMode.demo,
                              onChanged: (_) => _toggleSessionMode(
                                context,
                                ref,
                                serverConfig.mode,
                              ),
                            ),
                          ),
                          _SettingsTile(
                            icon: Icons.data_usage_rounded,
                            title: 'Network & Data Inspector',
                            subtitle:
                                'Inspect outgoing & incoming REST / WS payloads',
                            trailing: const Icon(Icons.chevron_right_rounded),
                            onTap: () => TbNetworkInspectorDialog.show(context),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: DesignTokens.spacing20),

                    // Notification Delivery Settings
                    _SectionHeader(title: 'Notification Delivery'),
                    TbStaggeredEntry(
                      index: 4,
                      child: notifSettingsAsync.when(
                        data: (settings) => _NotificationDeliveryCard(
                          settings: settings,
                          onSave: (updated) => ref
                              .read(notificationSettingsProvider.notifier)
                              .save(updated),
                        ),
                        loading: () => const TbShimmer(height: 120),
                        error: (_, _) => const SizedBox.shrink(),
                      ),
                    ),
                    const SizedBox(height: DesignTokens.spacing24),

                    // Logout Button
                    TbStaggeredEntry(
                      index: 5,
                      child: Semantics(
                        button: true,
                        label: 'Log out',
                        child: OutlinedButton.icon(
                          key: const Key('profile_logout_button'),
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
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _openEditProfileSheet(
    BuildContext context,
    WidgetRef ref,
    TbUserProfile user,
  ) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => _EditProfileSheet(user: user),
    );
  }

  void _openChangePasswordSheet(
    BuildContext context,
    WidgetRef ref,
    UserPasswordPolicy? policy,
  ) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => _ChangePasswordSheet(policy: policy),
    );
  }

  Future<void> _openServerDialog(
    BuildContext context,
    WidgetRef ref,
    String currentUrl,
  ) async {
    final controller = TextEditingController(text: currentUrl);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) {
        return AlertDialog(
          title: const Text('Switch Server URL'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Switching server clears active tokens and resets connections.',
              ),
              const SizedBox(height: DesignTokens.spacing16),
              TextField(
                controller: controller,
                decoration: const InputDecoration(
                  labelText: 'Server Base URL',
                  hintText: 'https://thingsboard.cloud',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogCtx).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogCtx).pop(true),
              child: const Text('Switch'),
            ),
          ],
        );
      },
    );

    if (confirmed == true && controller.text.trim().isNotEmpty) {
      await ref
          .read(serverConfigProvider.notifier)
          .switchServerUrl(controller.text.trim());
    }
  }

  Future<void> _toggleSessionMode(
    BuildContext context,
    WidgetRef ref,
    SessionMode currentMode,
  ) async {
    final targetMode = currentMode == SessionMode.live
        ? SessionMode.demo
        : SessionMode.live;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) {
        return AlertDialog(
          title: Text(
            targetMode == SessionMode.demo
                ? 'Enter Demo Mode?'
                : 'Exit Demo Mode?',
          ),
          content: Text(
            targetMode == SessionMode.demo
                ? 'Demo mode uses offline sample data. Active live tokens will be cleared.'
                : 'Switching to Live mode connects to the server and requires sign-in.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogCtx).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogCtx).pop(true),
              child: const Text('Confirm'),
            ),
          ],
        );
      },
    );

    if (confirmed == true) {
      await ref.read(serverConfigProvider.notifier).setSessionMode(targetMode);
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
}

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({
    required this.user,
    required this.mode,
    required this.onEditProfile,
  });

  final TbUserProfile user;
  final SessionMode mode;
  final VoidCallback onEditProfile;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Material(
      color: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: DesignTokens.borderRadiusLarge,
        side: BorderSide(color: scheme.outlineVariant),
      ),
      child: Padding(
        padding: DesignTokens.cardPadding,
        child: Row(
          children: [
            CircleAvatar(
              radius: 28,
              backgroundColor: scheme.primaryContainer,
              foregroundColor: scheme.onPrimaryContainer,
              child: Text(
                user.initials,
                style: textTheme.titleMedium?.copyWith(
                  color: scheme.onPrimaryContainer,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: DesignTokens.spacing16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    user.displayName,
                    style: textTheme.titleMedium?.copyWith(
                      color: scheme.onSurface,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    user.email,
                    style: textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: DesignTokens.spacing8),
                  Wrap(
                    spacing: DesignTokens.spacing8,
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
                      if (user.phone.isNotEmpty)
                        Text(
                          user.phone,
                          style: textTheme.labelSmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Edit profile',
              constraints: const BoxConstraints(
                minWidth: DesignTokens.minTouchTarget,
                minHeight: DesignTokens.minTouchTarget,
              ),
              icon: const Icon(Icons.edit_outlined),
              onPressed: onEditProfile,
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.only(
        left: DesignTokens.spacing4,
        bottom: DesignTokens.spacing8,
      ),
      child: Text(
        title,
        style: textTheme.labelLarge?.copyWith(color: scheme.onSurfaceVariant),
      ),
    );
  }
}

class _SettingsGroup extends StatelessWidget {
  const _SettingsGroup({required this.children});

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

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.trailing,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Semantics(
      button: onTap != null,
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
                Icon(
                  icon,
                  size: DesignTokens.iconMedium,
                  color: scheme.primary,
                ),
                const SizedBox(width: DesignTokens.spacing16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
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
                if (trailing != null) ...[
                  const SizedBox(width: DesignTokens.spacing8),
                  trailing!,
                ] else if (onTap != null) ...[
                  const SizedBox(width: DesignTokens.spacing8),
                  Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NotificationDeliveryCard extends StatelessWidget {
  const _NotificationDeliveryCard({
    required this.settings,
    required this.onSave,
  });

  final TbUserNotificationSettings settings;
  final ValueChanged<TbUserNotificationSettings> onSave;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final alarmPrefs =
        settings.prefs['ALARM'] as Map<String, dynamic>? ?? const {};

    final isWebEnabled = alarmPrefs['WEB'] as bool? ?? true;
    final isMobileEnabled = alarmPrefs['MOBILE_APP'] as bool? ?? true;
    final isEmailEnabled = alarmPrefs['EMAIL'] as bool? ?? false;

    void update(String channel, bool enabled) {
      final updatedPrefs = Map<String, dynamic>.from(settings.prefs);
      final updatedAlarm = Map<String, dynamic>.from(alarmPrefs);
      updatedAlarm[channel] = enabled;
      updatedPrefs['ALARM'] = updatedAlarm;
      onSave(TbUserNotificationSettings(prefs: updatedPrefs));
    }

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
            Text(
              'Alarm Notification Channels',
              style: textTheme.titleSmall?.copyWith(
                color: scheme.onSurface,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: DesignTokens.spacing12),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: const Text('In-App Web Alerts'),
              value: isWebEnabled,
              onChanged: (val) => update('WEB', val),
            ),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: const Text('Mobile Push Notifications'),
              value: isMobileEnabled,
              onChanged: (val) => update('MOBILE_APP', val),
            ),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: const Text('Email Alerts'),
              value: isEmailEnabled,
              onChanged: (val) => update('EMAIL', val),
            ),
          ],
        ),
      ),
    );
  }
}

class _EditProfileSheet extends ConsumerStatefulWidget {
  const _EditProfileSheet({required this.user});

  final TbUserProfile user;

  @override
  ConsumerState<_EditProfileSheet> createState() => _EditProfileSheetState();
}

class _EditProfileSheetState extends ConsumerState<_EditProfileSheet> {
  late final TextEditingController _firstCtrl;
  late final TextEditingController _lastCtrl;
  late final TextEditingController _phoneCtrl;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _firstCtrl = TextEditingController(text: widget.user.firstName);
    _lastCtrl = TextEditingController(text: widget.user.lastName);
    _phoneCtrl = TextEditingController(text: widget.user.phone);
  }

  @override
  void dispose() {
    _firstCtrl.dispose();
    _lastCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final updated = widget.user.copyWith(
        firstName: _firstCtrl.text.trim(),
        lastName: _lastCtrl.text.trim(),
        phone: _phoneCtrl.text.trim(),
      );
      await ref
          .read(userProfileControllerProvider.notifier)
          .updateProfile(updated);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to update: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: EdgeInsets.only(
        left: DesignTokens.spacing16,
        right: DesignTokens.spacing16,
        top: DesignTokens.spacing16,
        bottom:
            MediaQuery.of(context).viewInsets.bottom + DesignTokens.spacing20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Edit Profile',
            style: textTheme.titleMedium?.copyWith(
              color: scheme.onSurface,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: DesignTokens.spacing16),
          TextField(
            controller: _firstCtrl,
            decoration: const InputDecoration(
              labelText: 'First Name',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: DesignTokens.spacing12),
          TextField(
            controller: _lastCtrl,
            decoration: const InputDecoration(
              labelText: 'Last Name',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: DesignTokens.spacing12),
          TextField(
            controller: _phoneCtrl,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(
              labelText: 'Phone',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: DesignTokens.spacing20),
          FilledButton(
            style: FilledButton.styleFrom(
              minimumSize: const Size(
                double.infinity,
                DesignTokens.minTouchTarget,
              ),
            ),
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Save Profile'),
          ),
        ],
      ),
    );
  }
}

class _ChangePasswordSheet extends ConsumerStatefulWidget {
  const _ChangePasswordSheet({this.policy});

  final UserPasswordPolicy? policy;

  @override
  ConsumerState<_ChangePasswordSheet> createState() =>
      _ChangePasswordSheetState();
}

class _ChangePasswordSheetState extends ConsumerState<_ChangePasswordSheet> {
  final _currentCtrl = TextEditingController();
  final _newCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  String? _errorText;
  bool _saving = false;

  @override
  void dispose() {
    _currentCtrl.dispose();
    _newCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  String? _validatePassword(String password) {
    final policy = widget.policy;
    if (policy != null) {
      if (password.length < policy.minimumLength) {
        return 'Password must be at least ${policy.minimumLength} characters';
      }
      if (policy.minimumUppercaseLetters != null &&
          policy.minimumUppercaseLetters! > 0 &&
          !RegExp(r'[A-Z]').hasMatch(password)) {
        return 'Must contain uppercase letters';
      }
      if (policy.minimumDigits != null &&
          policy.minimumDigits! > 0 &&
          !RegExp(r'[0-9]').hasMatch(password)) {
        return 'Must contain numeric digits';
      }
      if (policy.minimumSpecialCharacters != null &&
          policy.minimumSpecialCharacters! > 0 &&
          !RegExp(r'[!@#$%^&*(),.?":{}|<>]').hasMatch(password)) {
        return 'Must contain special characters';
      }
    } else if (password.length < 6) {
      return 'Password must be at least 6 characters';
    }
    return null;
  }

  Future<void> _submit() async {
    final current = _currentCtrl.text;
    final newPass = _newCtrl.text;
    final confirm = _confirmCtrl.text;

    if (current.isEmpty) {
      setState(() => _errorText = 'Current password is required');
      return;
    }

    final validationError = _validatePassword(newPass);
    if (validationError != null) {
      setState(() => _errorText = validationError);
      return;
    }

    if (newPass != confirm) {
      setState(() => _errorText = 'New passwords do not match');
      return;
    }

    setState(() {
      _errorText = null;
      _saving = true;
    });

    try {
      await ref
          .read(userProfileControllerProvider.notifier)
          .changePassword(currentPassword: current, newPassword: newPass);
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Password changed successfully')),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorText = e is TbFailure ? e.message : e.toString();
        });
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: EdgeInsets.only(
        left: DesignTokens.spacing16,
        right: DesignTokens.spacing16,
        top: DesignTokens.spacing16,
        bottom:
            MediaQuery.of(context).viewInsets.bottom + DesignTokens.spacing20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Change Password',
            style: textTheme.titleMedium?.copyWith(
              color: scheme.onSurface,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (_errorText != null) ...[
            const SizedBox(height: DesignTokens.spacing8),
            Container(
              padding: DesignTokens.cardPadding,
              decoration: BoxDecoration(
                color: scheme.errorContainer,
                borderRadius: DesignTokens.borderRadiusMedium,
              ),
              child: Text(
                _errorText!,
                style: textTheme.bodySmall?.copyWith(
                  color: scheme.onErrorContainer,
                ),
              ),
            ),
          ],
          const SizedBox(height: DesignTokens.spacing16),
          TextField(
            controller: _currentCtrl,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'Current Password',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: DesignTokens.spacing12),
          TextField(
            controller: _newCtrl,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'New Password',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: DesignTokens.spacing12),
          TextField(
            controller: _confirmCtrl,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'Confirm New Password',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: DesignTokens.spacing20),
          FilledButton(
            style: FilledButton.styleFrom(
              minimumSize: const Size(
                double.infinity,
                DesignTokens.minTouchTarget,
              ),
            ),
            onPressed: _saving ? null : _submit,
            child: _saving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Update Password'),
          ),
        ],
      ),
    );
  }
}
