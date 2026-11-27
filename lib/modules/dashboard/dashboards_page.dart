import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:thingsboard_democloud_app/config/routes/router.dart';
import 'package:thingsboard_democloud_app/config/themes/design_tokens.dart';
import 'package:thingsboard_democloud_app/config/themes/tb_text_styles.dart';
import 'package:thingsboard_democloud_app/core/api/controllers/dashboard_controller.dart';
import 'package:thingsboard_democloud_app/core/models/dashboard_models.dart';
import 'package:thingsboard_democloud_app/core/models/pagination.dart';
import 'package:thingsboard_democloud_app/core/models/tb_failure.dart';
import 'package:thingsboard_democloud_app/modules/dashboard/dashboard_details_page.dart';
import 'package:thingsboard_democloud_app/widgets/icons/tb_icons.dart';
import 'package:thingsboard_democloud_app/widgets/tb_app_bar.dart';
import 'package:thingsboard_democloud_app/widgets/tb_app_search_bar.dart';
import 'package:thingsboard_democloud_app/widgets/tb_empty_state.dart';
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

  void _maybeEnsureStarredCoverage(
    PagedListState<TbDashboardInfo> paged,
    int visibleStarredCount,
  ) {
    if (!_starredOnly ||
        !paged.hasNext ||
        paged.isLoadingMore ||
        paged.loadMoreError != null) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_starredOnly) return;
      final cannotScroll =
          visibleStarredCount == 0 ||
          (_scrollController.hasClients &&
              _scrollController.position.maxScrollExtent <= 0);
      if (cannotScroll) {
        ref.read(dashboardsListProvider(_searchQuery).notifier).loadNextPage();
      }
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

    final filterBar = _FilterChipBar(
      starredOnly: _starredOnly,
      onChanged: (starred) => setState(() => _starredOnly = starred),
    );

    return Scaffold(
      appBar: appBar,
      body: SafeArea(
        bottom: false,
        child: dashboardsAsync.when(
          loading: () => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              filterBar,
              Expanded(
                child: SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(
                    DesignTokens.spacing16,
                    DesignTokens.spacing4,
                    DesignTokens.spacing16,
                    DesignTokens.bottomScrollPadding(context),
                  ),
                  child: const TbShimmerList(itemCount: 4),
                ),
              ),
            ],
          ),
          error: (error, _) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              filterBar,
              Expanded(
                child: TbEmptyState(
                  icon: TbIconKind.dashboardTile,
                  title: 'Failed to load',
                  subtitle: error is TbFailure ? error.message : null,
                  actionLabel: 'Retry',
                  isError: true,
                  onAction: () => ref
                      .read(dashboardsListProvider(_searchQuery).notifier)
                      .refresh(),
                ),
              ),
            ],
          ),
          data: (paged) {
            final items = _starredOnly
                ? paged.items.where((d) => d.isStarred).toList(growable: false)
                : paged.items;

            _maybeEnsureStarredCoverage(paged, items.length);

            Widget buildEmptyState() {
              if (_starredOnly &&
                  paged.hasNext &&
                  paged.loadMoreError == null) {
                return SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(
                    DesignTokens.spacing16,
                    DesignTokens.spacing4,
                    DesignTokens.spacing16,
                    DesignTokens.bottomScrollPadding(context),
                  ),
                  child: const TbShimmerList(itemCount: 3),
                );
              }
              final hasFilters = _starredOnly || _searchQuery != null;
              return TbEmptyState(
                icon: TbIconKind.dashboardTile,
                title: _starredOnly ? 'No starred dashboards' : 'No dashboards',
                actionLabel: hasFilters ? 'Clear filters' : 'Refresh',
                onAction: hasFilters
                    ? _clearFilters
                    : () => ref
                          .read(dashboardsListProvider(_searchQuery).notifier)
                          .refresh(),
              );
            }

            if (!isTwoPane || paged.items.isEmpty) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  filterBar,
                  Expanded(
                    child: items.isEmpty
                        ? buildEmptyState()
                        : _buildCollection(
                            context,
                            paged: paged,
                            items: items,
                            isTwoPane: false,
                            selectedId: null,
                          ),
                  ),
                ],
              );
            }

            final activeId = items.any((d) => d.id == _selectedDashboardId)
                ? _selectedDashboardId!
                : paged.items.any((d) => d.id == _selectedDashboardId)
                ? _selectedDashboardId!
                : (items.firstOrNull ?? paged.items.first).id;

            return Row(
              children: [
                SizedBox(
                  width: 360,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      filterBar,
                      Expanded(
                        child: items.isEmpty
                            ? buildEmptyState()
                            : _buildCollection(
                                context,
                                paged: paged,
                                items: items,
                                isTwoPane: true,
                                selectedId: activeId,
                              ),
                      ),
                    ],
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
    );
  }

  Widget _buildCollection(
    BuildContext context, {
    required PagedListState<TbDashboardInfo> paged,
    required List<TbDashboardInfo> items,
    required bool isTwoPane,
    required String? selectedId,
  }) {
    final rowCount = items.length;
    final hasFooter = paged.isLoadingMore || paged.loadMoreError != null;

    return RefreshIndicator(
      onRefresh: () =>
          ref.read(dashboardsListProvider(_searchQuery).notifier).refresh(),
      child: ListView.builder(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(
          DesignTokens.spacing16,
          DesignTokens.spacing4,
          DesignTokens.spacing16,
          DesignTokens.bottomScrollPadding(context),
        ),
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

          final item = items[rowIndex];
          return Padding(
            padding: const EdgeInsets.only(bottom: DesignTokens.spacing8),
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
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(
        horizontal: DesignTokens.spacing16,
        vertical: DesignTokens.spacing8,
      ),
      child: Row(
        spacing: DesignTokens.spacing8,
        children: [
          FilterChip(
            materialTapTargetSize: MaterialTapTargetSize.padded,
            label: const Text('All'),
            selected: !starredOnly,
            onSelected: (_) => onChanged(false),
          ),
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

  /// Single meta line: first two metric values, else first assigned customer.
  String? get _meta {
    if (dashboard.metrics.isNotEmpty) {
      return dashboard.metrics.values.take(2).join(' · ');
    }
    return dashboard.assignedCustomers.firstOrNull;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final disableAnimations = MediaQuery.disableAnimationsOf(context);
    final meta = _meta;

    final badge = Container(
      width: DesignTokens.iconXl,
      height: DesignTokens.iconXl,
      alignment: Alignment.center,
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

    final starIcon = Icon(
      dashboard.isStarred ? Icons.star_rounded : Icons.star_outline_rounded,
      color: dashboard.isStarred ? scheme.tertiary : scheme.onSurfaceVariant,
    );

    return Semantics(
      button: true,
      selected: selected,
      label: dashboard.title,
      child: Material(
        key: Key('dashboard-card-${dashboard.id}'),
        color: selected
            ? scheme.secondaryContainer.withValues(alpha: 0.65)
            : scheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: DesignTokens.borderRadiusLarge,
          side: BorderSide(
            color: selected ? scheme.primary : scheme.outlineVariant,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: TbPressScale(
          onTap: onTap,
          borderRadius: DesignTokens.borderRadiusLarge,
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minHeight: DesignTokens.minTouchTarget,
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                DesignTokens.spacing16,
                DesignTokens.spacing8,
                DesignTokens.spacing4,
                DesignTokens.spacing8,
              ),
              child: Row(
                children: [
                  if (enableHero)
                    Hero(tag: 'dashboard-${dashboard.id}', child: badge)
                  else
                    badge,
                  const SizedBox(width: DesignTokens.spacing12),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: DesignTokens.spacing4,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        spacing: DesignTokens.spacing2,
                        children: [
                          Text(
                            dashboard.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: textTheme.titleSmall?.copyWith(
                              color: scheme.onSurface,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (meta != null)
                            Text(
                              meta,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TbTextStyles.tabular(
                                textTheme.bodySmall ?? TbTextStyles.bodySmall,
                              ).copyWith(color: scheme.onSurfaceVariant),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: DesignTokens.spacing4),
                  IconButton(
                    key: Key('dashboard-star-${dashboard.id}'),
                    tooltip: dashboard.isStarred ? 'Unstar' : 'Star',
                    constraints: const BoxConstraints(
                      minWidth: DesignTokens.minTouchTarget,
                      minHeight: DesignTokens.minTouchTarget,
                    ),
                    padding: DesignTokens.paddingZero,
                    icon: disableAnimations
                        ? starIcon
                        : AnimatedScale(
                            scale: dashboard.isStarred ? 1.1 : 1.0,
                            duration: DesignTokens.motionFast,
                            curve: Curves.easeOutBack,
                            child: starIcon,
                          ),
                    onPressed: onToggleStar,
                  ),
                ],
              ),
            ),
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
