import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:thingsboard_democloud_app/config/themes/design_tokens.dart';
import 'package:thingsboard_democloud_app/core/api/controllers/customer_controller.dart';
import 'package:thingsboard_democloud_app/core/models/customer_models.dart';
import 'package:thingsboard_democloud_app/core/models/tb_failure.dart';
import 'package:thingsboard_democloud_app/widgets/icons/tb_icons.dart';
import 'package:thingsboard_democloud_app/widgets/tb_app_bar.dart';
import 'package:thingsboard_democloud_app/widgets/tb_empty_state.dart';
import 'package:thingsboard_democloud_app/widgets/tb_motion.dart';
import 'package:thingsboard_democloud_app/widgets/tb_shimmer.dart';
import 'package:url_launcher/url_launcher.dart';

/// Customer details screen displaying contact info, location, address, and quick actions.
class CustomerDetailsPage extends ConsumerWidget {
  const CustomerDetailsPage({
    super.key,
    required this.customerId,
    this.embedded = false,
    this.onLaunchUrl,
  });

  final String customerId;
  final bool embedded;
  final Future<bool> Function(Uri uri)? onLaunchUrl;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final customerAsync = ref.watch(customerDetailsProvider(customerId));
    final scheme = Theme.of(context).colorScheme;

    final content = customerAsync.when(
      data: (customer) => _CustomerDetailsBody(
        customer: customer,
        onRefresh: () =>
            ref.refresh(customerDetailsProvider(customerId).future),
        onLaunchUrl: onLaunchUrl ?? _defaultLaunchUrl,
      ),
      loading: () => const _CustomerDetailsShimmer(),
      error: (error, _) {
        final failure = error is TbFailure ? error : null;
        final is403 = failure?.type == TbFailureType.permissionDenied;
        return TbEmptyState(
          icon: TbIconKind.customerOrg,
          title: is403 ? 'Access Restricted' : 'Failed to load customer',
          subtitle: is403
              ? 'You do not have permission to view this customer organization.'
              : (failure?.message ?? error.toString()),
          actionLabel: is403 ? null : 'Retry',
          onAction: is403
              ? null
              : () => ref.invalidate(customerDetailsProvider(customerId)),
          isError: true,
        );
      },
    );

    if (embedded) {
      return Container(color: scheme.surface, child: content);
    }

    final title = customerAsync.valueOrNull?.title ?? 'Customer Details';
    return Scaffold(
      appBar: TbAppBar(canGoBack: true, title: Text(title)),
      body: SafeArea(child: content),
    );
  }

  static Future<bool> _defaultLaunchUrl(Uri uri) async {
    try {
      if (await canLaunchUrl(uri)) {
        return await launchUrl(uri);
      }
    } catch (_) {}
    return false;
  }
}

class _CustomerDetailsBody extends StatelessWidget {
  const _CustomerDetailsBody({
    required this.customer,
    required this.onRefresh,
    required this.onLaunchUrl,
  });

  final TbCustomerInfo customer;
  final Future<void> Function() onRefresh;
  final Future<bool> Function(Uri uri) onLaunchUrl;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final formattedCreated = customer.createdTime > 0
        ? DateFormat.yMMMd().format(
            DateTime.fromMillisecondsSinceEpoch(customer.createdTime),
          )
        : null;

    final hasPhone = customer.phone.trim().isNotEmpty;
    final hasEmail = customer.email.trim().isNotEmpty;
    final hasAddress =
        customer.address.trim().isNotEmpty ||
        customer.address2.trim().isNotEmpty ||
        customer.city.trim().isNotEmpty ||
        customer.state.trim().isNotEmpty ||
        customer.zip.trim().isNotEmpty ||
        customer.country.trim().isNotEmpty;

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: DesignTokens.maxReadableWidth,
          ),
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: DesignTokens.paddingMedium,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TbStaggeredEntry(
                  index: 0,
                  child: Material(
                    color: scheme.surfaceContainerLow,
                    shape: RoundedRectangleBorder(
                      borderRadius: DesignTokens.borderRadiusLarge,
                      side: BorderSide(color: scheme.outlineVariant),
                    ),
                    child: Padding(
                      padding: DesignTokens.cardPadding,
                      child: Row(
                        children: [
                          Container(
                            width: 52,
                            height: 52,
                            decoration: BoxDecoration(
                              color: scheme.primaryContainer,
                              shape: BoxShape.circle,
                            ),
                            child: Center(
                              child: TbIcon(
                                TbIconKind.customerOrg,
                                size: DesignTokens.iconLarge,
                                color: scheme.onPrimaryContainer,
                              ),
                            ),
                          ),
                          const SizedBox(width: DesignTokens.spacing16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  customer.title,
                                  style: textTheme.titleMedium?.copyWith(
                                    color: scheme.onSurface,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                if (formattedCreated != null) ...[
                                  const SizedBox(height: DesignTokens.spacing4),
                                  Text(
                                    'Created $formattedCreated',
                                    style: textTheme.bodySmall?.copyWith(
                                      color: scheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: DesignTokens.spacing16),
                if (hasPhone || hasEmail) ...[
                  Padding(
                    padding: const EdgeInsets.only(
                      left: DesignTokens.spacing4,
                      bottom: DesignTokens.spacing8,
                    ),
                    child: Text(
                      'Contact Information',
                      style: textTheme.labelLarge?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  TbStaggeredEntry(
                    index: 1,
                    child: Material(
                      color: scheme.surfaceContainerLow,
                      shape: RoundedRectangleBorder(
                        borderRadius: DesignTokens.borderRadiusLarge,
                        side: BorderSide(color: scheme.outlineVariant),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (hasEmail)
                            _ActionInfoTile(
                              icon: Icons.email_outlined,
                              label: 'Email',
                              value: customer.email,
                              actionTooltip: 'Send email',
                              onAction: () => onLaunchUrl(
                                Uri.parse('mailto:${customer.email}'),
                              ),
                            ),
                          if (hasPhone && hasEmail)
                            Divider(
                              height: 1,
                              thickness: 1,
                              indent: 56,
                              color: scheme.outlineVariant,
                            ),
                          if (hasPhone)
                            _ActionInfoTile(
                              icon: Icons.phone_outlined,
                              label: 'Phone',
                              value: customer.phone,
                              actionTooltip: 'Call phone',
                              onAction: () => onLaunchUrl(
                                Uri.parse('tel:${customer.phone}'),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: DesignTokens.spacing16),
                ],
                Padding(
                  padding: const EdgeInsets.only(
                    left: DesignTokens.spacing4,
                    bottom: DesignTokens.spacing8,
                  ),
                  child: Text(
                    'Location & Address',
                    style: textTheme.labelLarge?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
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
                          if (customer.locationSummary.isNotEmpty) ...[
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(
                                  Icons.place_outlined,
                                  size: DesignTokens.iconSmall,
                                  color: scheme.primary,
                                ),
                                const SizedBox(width: DesignTokens.spacing8),
                                Expanded(
                                  child: Text(
                                    customer.locationSummary,
                                    style: textTheme.bodyLarge?.copyWith(
                                      color: scheme.onSurface,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: DesignTokens.spacing12),
                          ],
                          if (customer.address.isNotEmpty)
                            _AddressLine(
                              label: 'Address',
                              value: customer.address,
                            ),
                          if (customer.address2.isNotEmpty)
                            _AddressLine(
                              label: 'Address 2',
                              value: customer.address2,
                            ),
                          if (customer.zip.isNotEmpty)
                            _AddressLine(
                              label: 'ZIP / Postal Code',
                              value: customer.zip,
                            ),
                          if (!hasAddress)
                            Text(
                              'No address on record',
                              style: textTheme.bodyMedium?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ActionInfoTile extends StatelessWidget {
  const _ActionInfoTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.actionTooltip,
    required this.onAction,
  });

  final IconData icon;
  final String label;
  final String value;
  final String actionTooltip;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return InkWell(
      onTap: onAction,
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
              Icon(icon, size: DesignTokens.iconMedium, color: scheme.primary),
              const SizedBox(width: DesignTokens.spacing16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      label,
                      style: textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    Text(
                      value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.bodyLarge?.copyWith(
                        color: scheme.onSurface,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: actionTooltip,
                constraints: const BoxConstraints(
                  minWidth: DesignTokens.minTouchTarget,
                  minHeight: DesignTokens.minTouchTarget,
                ),
                icon: const Icon(Icons.open_in_new_rounded),
                onPressed: onAction,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AddressLine extends StatelessWidget {
  const _AddressLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: DesignTokens.spacing8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: textTheme.bodyMedium?.copyWith(color: scheme.onSurface),
            ),
          ),
        ],
      ),
    );
  }
}

class _CustomerDetailsShimmer extends StatelessWidget {
  const _CustomerDetailsShimmer();

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: DesignTokens.paddingMedium,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: const [
          TbShimmer(height: 84),
          SizedBox(height: DesignTokens.spacing16),
          TbShimmer(height: 120),
          SizedBox(height: DesignTokens.spacing16),
          TbShimmer(height: 140),
        ],
      ),
    );
  }
}
