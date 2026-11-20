import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:thingsboard_democloud_app/config/routes/router.dart';
import 'package:thingsboard_democloud_app/config/themes/design_tokens.dart';
import 'package:thingsboard_democloud_app/core/api/controllers/customer_controller.dart';
import 'package:thingsboard_democloud_app/core/models/customer_models.dart';
import 'package:thingsboard_democloud_app/core/models/tb_failure.dart';
import 'package:thingsboard_democloud_app/modules/customer/customer_details_page.dart';
import 'package:thingsboard_democloud_app/widgets/icons/tb_icons.dart';
import 'package:thingsboard_democloud_app/widgets/tb_app_bar.dart';
import 'package:thingsboard_democloud_app/widgets/tb_app_search_bar.dart';
import 'package:thingsboard_democloud_app/widgets/tb_empty_state.dart';
import 'package:thingsboard_democloud_app/widgets/tb_motion.dart';
import 'package:thingsboard_democloud_app/widgets/tb_shimmer.dart';

/// Customers catalog screen with debounced search, infinite scroll pagination,
/// pull-to-refresh, RBAC 403 handling, and adaptive 2-pane master-detail.
class CustomersPage extends ConsumerStatefulWidget {
  const CustomersPage({super.key});

  @override
  ConsumerState<CustomersPage> createState() => _CustomersPageState();
}

class _CustomersPageState extends ConsumerState<CustomersPage> {
  final ScrollController _scrollController = ScrollController();
  String? _searchQuery;
  bool _isSearching = false;
  String? _selectedCustomerId;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final max = _scrollController.position.maxScrollExtent;
    final current = _scrollController.offset;
    if (current >= max - 240) {
      ref.read(customersListProvider(_searchQuery).notifier).loadNextPage();
    }
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _handleSearch(String query) {
    final trimmed = query.trim();
    final newSearch = trimmed.isEmpty ? null : trimmed;
    if (newSearch != _searchQuery) {
      setState(() {
        _searchQuery = newSearch;
      });
    }
  }

  void _closeSearch() {
    setState(() {
      _isSearching = false;
      _searchQuery = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final width = MediaQuery.sizeOf(context).width;
    final isTwoPane = width >= DesignTokens.mediumMaxWidth;
    final customersAsync = ref.watch(customersListProvider(_searchQuery));

    final appBar = _isSearching
        ? TbAppSearchBar(
            searchHint: 'Search customers...',
            onSearch: _handleSearch,
            leading: IconButton(
              tooltip: 'Close search',
              constraints: const BoxConstraints(
                minWidth: DesignTokens.minTouchTarget,
                minHeight: DesignTokens.minTouchTarget,
              ),
              icon: const Icon(Icons.arrow_back),
              onPressed: _closeSearch,
            ),
          )
        : TbAppBar(
            canGoBack: true,
            title: const Text('Customers'),
            actions: [
              IconButton(
                tooltip: 'Search customers',
                constraints: const BoxConstraints(
                  minWidth: DesignTokens.minTouchTarget,
                  minHeight: DesignTokens.minTouchTarget,
                ),
                icon: const Icon(Icons.search),
                onPressed: () => setState(() => _isSearching = true),
              ),
            ],
          );

    final listContent = customersAsync.when(
      error: (error, _) {
        final failure = error is TbFailure ? error : null;
        final is403 = failure?.type == TbFailureType.permissionDenied;
        return TbEmptyState(
          icon: TbIconKind.customerOrg,
          title: is403 ? 'Access Restricted' : 'Failed to load customers',
          subtitle: is403
              ? 'You do not have permission to view customer organizations.'
              : (failure?.message ?? error.toString()),
          actionLabel: is403 ? null : 'Retry',
          onAction: is403
              ? null
              : () => ref
                    .read(customersListProvider(_searchQuery).notifier)
                    .refresh(),
          isError: true,
        );
      },
      loading: () => const SingleChildScrollView(
        padding: DesignTokens.paddingMedium,
        child: TbShimmerList(itemCount: 6),
      ),
      data: (pagedState) {
        if (pagedState.items.isEmpty) {
          final isFilterActive =
              _searchQuery != null && _searchQuery!.isNotEmpty;
          return TbEmptyState(
            icon: TbIconKind.customerOrg,
            title: isFilterActive
                ? 'No matching customers'
                : 'No customers available',
            subtitle: isFilterActive
                ? 'Try adjusting your search terms.'
                : 'Customer organizations will appear here.',
            actionLabel: isFilterActive ? 'Clear search' : null,
            onAction: isFilterActive ? _closeSearch : null,
          );
        }

        // Auto-select first item in 2-pane if none selected
        if (isTwoPane &&
            _selectedCustomerId == null &&
            pagedState.items.isNotEmpty) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && _selectedCustomerId == null) {
              setState(() {
                _selectedCustomerId = pagedState.items.first.id;
              });
            }
          });
        }

        return RefreshIndicator(
          onRefresh: () =>
              ref.read(customersListProvider(_searchQuery).notifier).refresh(),
          child: ListView.separated(
            controller: _scrollController,
            physics: const AlwaysScrollableScrollPhysics(),
            padding: DesignTokens.paddingMedium,
            itemCount:
                pagedState.items.length + (pagedState.isLoadingMore ? 1 : 0),
            separatorBuilder: (_, _) =>
                const SizedBox(height: DesignTokens.spacing8),
            itemBuilder: (context, index) {
              if (index >= pagedState.items.length) {
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      vertical: DesignTokens.spacing16,
                    ),
                    child: CircularProgressIndicator(),
                  ),
                );
              }

              final customer = pagedState.items[index];
              final isSelected =
                  isTwoPane && customer.id == _selectedCustomerId;

              return TbStaggeredEntry(
                index: index,
                child: _CustomerListCard(
                  customer: customer,
                  isSelected: isSelected,
                  onTap: () {
                    if (isTwoPane) {
                      setState(() {
                        _selectedCustomerId = customer.id;
                      });
                    } else {
                      final router = GoRouter.maybeOf(context);
                      if (router != null) {
                        context.push(
                          AppRoutes.customerDetailsPath(customer.id),
                        );
                      }
                    }
                  },
                ),
              );
            },
          ),
        );
      },
    );

    return Scaffold(
      appBar: appBar,
      body: SafeArea(
        child: isTwoPane
            ? Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(
                          maxWidth: DesignTokens.maxReadableWidth,
                        ),
                        child: listContent,
                      ),
                    ),
                  ),
                  VerticalDivider(
                    width: 1,
                    thickness: 1,
                    color: scheme.outlineVariant,
                  ),
                  Expanded(
                    flex: 3,
                    child: _selectedCustomerId != null
                        ? CustomerDetailsPage(
                            key: ValueKey(_selectedCustomerId),
                            customerId: _selectedCustomerId!,
                            embedded: true,
                          )
                        : Center(
                            child: Text(
                              'Select a customer to view details',
                              style: Theme.of(context).textTheme.bodyLarge
                                  ?.copyWith(color: scheme.onSurfaceVariant),
                            ),
                          ),
                  ),
                ],
              )
            : Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: DesignTokens.maxReadableWidth,
                  ),
                  child: listContent,
                ),
              ),
      ),
    );
  }
}

class _CustomerListCard extends StatelessWidget {
  const _CustomerListCard({
    required this.customer,
    required this.isSelected,
    required this.onTap,
  });

  final TbCustomerInfo customer;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final location = customer.locationSummary;
    final hasContact = customer.email.isNotEmpty || customer.phone.isNotEmpty;

    return Semantics(
      button: true,
      label: 'Customer ${customer.title}',
      child: Material(
        color: isSelected
            ? scheme.primaryContainer.withValues(alpha: 0.3)
            : scheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: DesignTokens.borderRadiusLarge,
          side: BorderSide(
            color: isSelected ? scheme.primary : scheme.outlineVariant,
            width: isSelected ? 1.5 : 1.0,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: TbPressScale(
          borderRadius: DesignTokens.borderRadiusLarge,
          onTap: onTap,
          child: Padding(
            padding: DesignTokens.cardPadding,
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: isSelected
                        ? scheme.primary
                        : scheme.surfaceContainerHigh,
                    borderRadius: DesignTokens.borderRadiusMedium,
                  ),
                  child: Center(
                    child: TbIcon(
                      TbIconKind.customerOrg,
                      size: DesignTokens.iconMedium,
                      color: isSelected ? scheme.onPrimary : scheme.primary,
                    ),
                  ),
                ),
                const SizedBox(width: DesignTokens.spacing12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        customer.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.titleSmall?.copyWith(
                          color: scheme.onSurface,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (location.isNotEmpty) ...[
                        const SizedBox(height: DesignTokens.spacing4),
                        Row(
                          children: [
                            Icon(
                              Icons.place_outlined,
                              size: DesignTokens.iconXs,
                              color: scheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: DesignTokens.spacing4),
                            Expanded(
                              child: Text(
                                location,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: textTheme.bodySmall?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                      if (hasContact) ...[
                        const SizedBox(height: DesignTokens.spacing4),
                        Text(
                          customer.email.isNotEmpty
                              ? customer.email
                              : customer.phone,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: textTheme.labelSmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: DesignTokens.spacing8),
                Icon(
                  Icons.chevron_right,
                  color: isSelected ? scheme.primary : scheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
