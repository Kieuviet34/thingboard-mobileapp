import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:thingsboard_democloud_app/config/routes/router.dart';
import 'package:thingsboard_democloud_app/config/themes/design_tokens.dart';
import 'package:thingsboard_democloud_app/core/api/controllers/dashboard_controller.dart';
import 'package:thingsboard_democloud_app/core/models/dashboard_models.dart';
import 'package:thingsboard_democloud_app/core/models/pagination.dart';
import 'package:thingsboard_democloud_app/core/models/tb_failure.dart';
import 'package:thingsboard_democloud_app/modules/dashboard/dashboard_details_page.dart';
import 'package:thingsboard_democloud_app/widgets/icons/tb_icons.dart';
import 'package:thingsboard_democloud_app/widgets/tb_app_bar.dart';
import 'package:thingsboard_democloud_app/widgets/tb_app_search_bar.dart';
import 'package:thingsboard_democloud_app/widgets/tb_empty_state.dart';
import 'package:thingsboard_democloud_app/widgets/tb_metric_pill.dart';
import 'package:thingsboard_democloud_app/widgets/tb_motion.dart';
import 'package:thingsboard_democloud_app/widgets/tb_shimmer.dart';

/// Material 3 dashboards gallery with search, All/Starred filters, pagination,
/// and adaptive 2-pane master-detail on `width >= 840dp`.
class DashboardsPage extends ConsumerStatefulWidget {
  const DashboardsPage({super.key});

  @override
  ConsumerState<DashboardsPage> createState() => _DashboardsPageState();
}

class _DashboardsPageState extends ConsumerState<DashboardsPage> {
  final ScrollController _scrollController = ScrollController();
  bool _isSearching = false;
  bool _starredOnly = false;
  String? _searchQuery;
  String? _selectedDashboardId;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;
    if (pos.pixels >= pos.maxScrollExtent - 200) {
      ref.read(dashboardsListProvider(_searchQuery).notifier).loadNextPage();
    }
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _clearFilters() {
    setState(() {
      _starredOnly = false;
      _searchQuery = null;
      _isSearching = false;
    });
  }

  void _onOpenDashboard(TbDashboardInfo dashboard, {required bool isTwoPane}) {
    if (isTwoPane) {
      setState(() => _selectedDashboardId = dashboard.id);
      return;
    }
    context.push(AppRoutes.dashboardDetailsPath(dashboard.id));
  }

  @override
  Widget build(BuildContext context) {
    final dashboardsAsync = ref.watch(dashboardsListProvider(_searchQuery));
    final width = MediaQuery.sizeOf(context).width;
    final isTwoPane = width >= DesignTokens.mediumMaxWidth;
    final scheme = Theme.of(context).colorScheme;

    final PreferredSizeWidget appBar = _isSearching
        ? TbAppSearchBar(
            searchHint: 'Search dashboards',
            leading: IconButton(
              tooltip: 'Close search',
              constraints: const BoxConstraints(
                minWidth: DesignTokens.minTouchTarget,
                minHeight: DesignTokens.minTouchTarget,
              ),
              icon: const Icon(Icons.arrow_back),
              onPressed: () {
                setState(() {
                  _isSearching = false;
                  _searchQuery = null;
                });
              },
            ),
            onSearch: (text) {
              final normalized = text.trim();
              setState(
                () => _searchQuery = normalized.isEmpty ? null : normalized,
              );
            },
          )
        : TbAppBar(
            title: const Text('Dashboards'),
            actions: [
              IconButton(
                tooltip: 'Search dashboards',
                constraints: const BoxConstraints(
                  minWidth: DesignTokens.minTouchTarget,
                  minHeight: DesignTokens.minTouchTarget,
                ),
                icon: const Icon(Icons.search),
                onPressed: () => setState(() => _isSearching = true),
              ),
            ],
          );

    return Scaffold(
      appBar: appBar,
      body: SafeArea(
        child: Column(
          children: [
            _FilterChipBar(
              starredOnly: _starredOnly,
              onChanged: (starred) => setState(() => _starredOnly = starred),
            ),
            Expanded(
              child: dashboardsAsync.when(
                loading: () => const SingleChildScrollView(
                  padding: DesignTokens.paddingMedium,
                  child: TbShimmerList(itemCount: 4),
                ),
                error: (error, _) => TbEmptyState(
                  icon: TbIconKind.dashboardTile,
                  title: 'Failed to load',
                  subtitle: error is TbFailure ? error.message : null,
                  actionLabel: 'Retry',
                  isError: true,
                  onAction: () => ref
                      .read(dashboardsListProvider(_searchQuery).notifier)
                      .refresh(),
                ),
                data: (paged) {
                  final items = _starredOnly
                      ? paged.items
                            .where((d) => d.isStarred)
                            .toList(growable: false)
                      : paged.items;

                  if (items.isEmpty) {
                    final hasFilters = _starredOnly || _searchQuery != null;
                    return TbEmptyState(
                      icon: TbIconKind.dashboardTile,
                      title: _starredOnly
                          ? 'No starred dashboards'
                          : 'No dashboards',
                      actionLabel: hasFilters ? 'Clear filters' : 'Refresh',
                      onAction: hasFilters
                          ? _clearFilters
                          : () => ref
                                .read(
                                  dashboardsListProvider(_searchQuery).notifier,
                                )
                                .refresh(),
                    );
                  }

                  if (!isTwoPane) {
                    return _buildCollection(
                      paged: paged,
                      items: items,
                      isTwoPane: false,
                      selectedId: null,
                    );
                  }

                  final activeId =
                      items.any((d) => d.id == _selectedDashboardId)
                      ? _selectedDashboardId!
                      : items.first.id;

                  return Row(
                    children: [
                      SizedBox(
                        width: 360,
                        child: _buildCollection(
                          paged: paged,
                          items: items,
                          isTwoPane: true,
                          selectedId: activeId,
                        ),
                      ),
                      VerticalDivider(
                        width: 1,
                        thickness: 1,
                        color: scheme.outlineVariant,
                      ),
                      Expanded(
                        child: DashboardDetailsPage(
                          key: ValueKey<String>(activeId),
                          dashboardId: activeId,
                          embedded: true,
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCollection({
    required PagedListState<TbDashboardInfo> paged,
    required List<TbDashboardInfo> items,
    required bool isTwoPane,
    required String? selectedId,
  }) {
    final columns = isTwoPane ? 1 : 2;
    final rowCount = (items.length / columns).ceil();
    final hasFooter = paged.isLoadingMore || paged.loadMoreError != null;

    return RefreshIndicator(
      onRefresh: () =>
          ref.read(dashboardsListProvider(_searchQuery).notifier).refresh(),
      child: ListView.builder(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: DesignTokens.paddingMedium,
        itemCount: rowCount + (hasFooter ? 1 : 0),
        itemBuilder: (context, rowIndex) {
          if (rowIndex >= rowCount) {
            return _PaginationFooter(
              isLoadingMore: paged.isLoadingMore,
              loadMoreError: paged.loadMoreError,
              onRetry: () => ref
                  .read(dashboardsListProvider(_searchQuery).notifier)
                  .loadNextPage(),
            );
          }

          if (columns == 1) {
            final item = items[rowIndex];
            return Padding(
              padding: const EdgeInsets.only(bottom: DesignTokens.spacing12),
              child: TbStaggeredEntry(
                index: rowIndex,
                child: _DashboardGalleryCard(
                  dashboard: item,
                  selected: item.id == selectedId,
                  enableHero: !isTwoPane,
                  onTap: () => _onOpenDashboard(item, isTwoPane: isTwoPane),
                  onToggleStar: () => ref
                      .read(dashboardsListProvider(_searchQuery).notifier)
                      .toggleStar(item.id),
                ),
              ),
            );
          }

          final leftIndex = rowIndex * 2;
          final rightIndex = leftIndex + 1;
          final leftItem = items[leftIndex];
          final rightItem = rightIndex < items.length
              ? items[rightIndex]
              : null;

          return Padding(
            padding: const EdgeInsets.only(bottom: DesignTokens.spacing12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TbStaggeredEntry(
                    index: leftIndex,
                    child: _DashboardGalleryCard(
                      dashboard: leftItem,
                      selected: false,
                      enableHero: true,
                      onTap: () =>
                          _onOpenDashboard(leftItem, isTwoPane: isTwoPane),
                      onToggleStar: () => ref
                          .read(dashboardsListProvider(_searchQuery).notifier)
                          .toggleStar(leftItem.id),
                    ),
                  ),
                ),
                const SizedBox(width: DesignTokens.spacing12),
                Expanded(
                  child: rightItem == null
                      ? const SizedBox.shrink()
                      : TbStaggeredEntry(
                          index: rightIndex,
                          child: _DashboardGalleryCard(
                            dashboard: rightItem,
                            selected: false,
                            enableHero: true,
                            onTap: () => _onOpenDashboard(
                              rightItem,
                              isTwoPane: isTwoPane,
                            ),
                            onToggleStar: () => ref
                                .read(
                                  dashboardsListProvider(_searchQuery).notifier,
                                )
                                .toggleStar(rightItem.id),
                          ),
                        ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _FilterChipBar extends StatelessWidget {
  const _FilterChipBar({required this.starredOnly, required this.onChanged});

  final bool starredOnly;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        DesignTokens.spacing16,
        DesignTokens.spacing8,
        DesignTokens.spacing16,
        DesignTokens.spacing4,
      ),
      child: Row(
        children: [
          FilterChip(
            materialTapTargetSize: MaterialTapTargetSize.padded,
            label: const Text('All'),
            selected: !starredOnly,
            onSelected: (_) => onChanged(false),
          ),
          const SizedBox(width: DesignTokens.spacing8),
          FilterChip(
            materialTapTargetSize: MaterialTapTargetSize.padded,
            label: const Text('Starred'),
            selected: starredOnly,
            onSelected: (_) => onChanged(true),
          ),
        ],
      ),
    );
  }
}

class _DashboardGalleryCard extends StatelessWidget {
  const _DashboardGalleryCard({
    required this.dashboard,
    required this.selected,
    required this.enableHero,
    required this.onTap,
    required this.onToggleStar,
  });

  final TbDashboardInfo dashboard;
  final bool selected;
  final bool enableHero;
  final VoidCallback onTap;
  final VoidCallback onToggleStar;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final disableAnimations = MediaQuery.disableAnimationsOf(context);
    final metrics = dashboard.metrics.entries.take(2).toList(growable: false);

    final badge = Container(
      padding: DesignTokens.paddingSmall,
      decoration: BoxDecoration(
        color: selected ? scheme.primary : scheme.primaryContainer,
        borderRadius: DesignTokens.borderRadiusMedium,
      ),
      child: TbIcon(
        TbIconKind.dashboardTile,
        size: DesignTokens.iconSmall,
        color: selected ? scheme.onPrimary : scheme.onPrimaryContainer,
      ),
    );

    return Semantics(
      button: true,
      selected: selected,
      label: dashboard.title,
      child: TbPressScale(
        onTap: onTap,
        borderRadius: DesignTokens.borderRadiusLarge,
        child: Container(
          key: Key('dashboard-card-${dashboard.id}'),
          padding: DesignTokens.cardPadding,
          decoration: BoxDecoration(
            color: selected
                ? scheme.secondaryContainer.withValues(alpha: 0.65)
                : scheme.surfaceContainerLow,
            borderRadius: DesignTokens.borderRadiusLarge,
            border: Border.all(
              color: selected ? scheme.primary : scheme.outlineVariant,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (enableHero)
                    Hero(tag: 'dashboard-${dashboard.id}', child: badge)
                  else
                    badge,
                  const Spacer(),
                  IconButton(
                    key: Key('dashboard-star-${dashboard.id}'),
                    tooltip: dashboard.isStarred ? 'Unstar' : 'Star',
                    constraints: const BoxConstraints(
                      minWidth: DesignTokens.minTouchTarget,
                      minHeight: DesignTokens.minTouchTarget,
                    ),
                    padding: DesignTokens.paddingZero,
                    icon: disableAnimations
                        ? Icon(
                            dashboard.isStarred
                                ? Icons.star_rounded
                                : Icons.star_outline_rounded,
                            color: dashboard.isStarred
                                ? scheme.tertiary
                                : scheme.onSurfaceVariant,
                          )
                        : AnimatedScale(
                            scale: dashboard.isStarred ? 1.1 : 1.0,
                            duration: DesignTokens.motionFast,
                            curve: Curves.easeOutBack,
                            child: Icon(
                              dashboard.isStarred
                                  ? Icons.star_rounded
                                  : Icons.star_outline_rounded,
                              color: dashboard.isStarred
                                  ? scheme.tertiary
                                  : scheme.onSurfaceVariant,
                            ),
                          ),
                    onPressed: onToggleStar,
                  ),
                ],
              ),
              const SizedBox(height: DesignTokens.spacing8),
              Text(
                dashboard.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: textTheme.titleSmall?.copyWith(
                  color: scheme.onSurface,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (metrics.isNotEmpty) ...[
                const SizedBox(height: DesignTokens.spacing8),
                Wrap(
                  spacing: DesignTokens.spacing8,
                  runSpacing: DesignTokens.spacing8,
                  children: [
                    for (final entry in metrics)
                      TbMetricPill(
                        icon: TbIcons.kindForTelemetryKey(entry.key),
                        value: entry.value,
                      ),
                  ],
                ),
              ] else if (dashboard.assignedCustomers.isNotEmpty) ...[
                const SizedBox(height: DesignTokens.spacing8),
                Text(
                  dashboard.assignedCustomers.first,
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
      ),
    );
  }
}

class _PaginationFooter extends StatelessWidget {
  const _PaginationFooter({
    required this.isLoadingMore,
    required this.loadMoreError,
    required this.onRetry,
  });

  final bool isLoadingMore;
  final TbFailure? loadMoreError;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    if (isLoadingMore) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: DesignTokens.spacing12),
        child: TbShimmer(height: 56),
      );
    }
    if (loadMoreError != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: DesignTokens.spacing12),
        child: Center(
          child: TextButton(onPressed: onRetry, child: const Text('Retry')),
        ),
      );
    }
    return const SizedBox.shrink();
  }
}
