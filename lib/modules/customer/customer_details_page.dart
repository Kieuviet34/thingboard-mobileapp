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
import 'package:thingsboard_democloud_app/widgets/tb_list_row.dart';
import 'package:thingsboard_democloud_app/widgets/tb_motion.dart';
import 'package:thingsboard_democloud_app/widgets/tb_section_card.dart';
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
        : '';

    final hasPhone = customer.phone.trim().isNotEmpty;
    final hasEmail = customer.email.trim().isNotEmpty;

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
                  child: Row(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: scheme.primaryContainer,
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: TbIcon(
                            TbIconKind.customerOrg,
                            size: DesignTokens.iconMedium,
                            color: scheme.onPrimaryContainer,
                          ),
                        ),
                      ),
                      const SizedBox(width: DesignTokens.spacing12),
                      Expanded(
                        child: Text(
                          customer.title,
                          style: textTheme.titleMedium?.copyWith(
                            color: scheme.onSurface,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: DesignTokens.spacing16),
                if (hasPhone || hasEmail) ...[
                  TbStaggeredEntry(
                    index: 1,
                    child: TbSectionCard(
                      title: 'Contact',
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (hasEmail)
                            _ContactRow(
                              icon: Icons.email_outlined,
                              label: 'Email',
                              value: customer.email,
                              actionTooltip: 'Send email',
                              onAction: () => onLaunchUrl(
                                Uri.parse('mailto:${customer.email}'),
                              ),
                            ),
                          if (hasPhone)
                            _ContactRow(
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
                TbStaggeredEntry(
                  index: 2,
                  child: TbSectionCard(
                    title: 'Details',
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TbKvRow(
                          label: 'Location',
                          value: customer.locationSummary,
                        ),
                        if (customer.address.isNotEmpty)
                          TbKvRow(label: 'Address', value: customer.address),
                        if (customer.address2.isNotEmpty)
                          TbKvRow(label: 'Address 2', value: customer.address2),
                        if (customer.zip.isNotEmpty)
                          TbKvRow(label: 'ZIP', value: customer.zip),
                        if (formattedCreated.isNotEmpty)
                          TbKvRow(label: 'Created', value: formattedCreated),
                      ],
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

class _ContactRow extends StatelessWidget {
  const _ContactRow({
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
    return TbListRow(
      title: value,
      meta: label,
      leading: Icon(icon, size: DesignTokens.iconMedium, color: scheme.primary),
      trailing: IconButton(
        tooltip: actionTooltip,
        constraints: const BoxConstraints(
          minWidth: DesignTokens.minTouchTarget,
          minHeight: DesignTokens.minTouchTarget,
        ),
        icon: const Icon(Icons.open_in_new_rounded),
        onPressed: onAction,
      ),
      onTap: onAction,
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
