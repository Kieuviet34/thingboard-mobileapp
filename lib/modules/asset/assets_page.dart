import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:thingsboard_democloud_app/config/routes/router.dart';
import 'package:thingsboard_democloud_app/config/themes/design_tokens.dart';
import 'package:thingsboard_democloud_app/core/api/controllers/asset_controller.dart';
import 'package:thingsboard_democloud_app/core/models/asset_models.dart';
import 'package:thingsboard_democloud_app/core/models/tb_failure.dart';
import 'package:thingsboard_democloud_app/modules/asset/asset_details_page.dart';
import 'package:thingsboard_democloud_app/widgets/icons/tb_icons.dart';
import 'package:thingsboard_democloud_app/widgets/tb_app_bar.dart';
import 'package:thingsboard_democloud_app/widgets/tb_app_search_bar.dart';
import 'package:thingsboard_democloud_app/widgets/tb_empty_state.dart';
import 'package:thingsboard_democloud_app/widgets/tb_list_row.dart';
import 'package:thingsboard_democloud_app/widgets/tb_motion.dart';
import 'package:thingsboard_democloud_app/widgets/tb_shimmer.dart';

/// Assets catalog screen with profile filter chips, debounced search,
/// infinite scroll pagination, and adaptive 2-pane master-detail.
class AssetsPage extends ConsumerStatefulWidget {
  const AssetsPage({super.key});

  @override
  ConsumerState<AssetsPage> createState() => _AssetsPageState();
}

class _AssetsPageState extends ConsumerState<AssetsPage> {
  final ScrollController _scrollController = ScrollController();
  String? _selectedProfileId;
  String? _searchQuery;
  bool _isSearching = false;
  String? _selectedAssetId;

  TbAssetQuery get _query => TbAssetQuery(
    assetProfileId: _selectedProfileId,
    textSearch: _searchQuery,
  );

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
      ref.read(assetsListProvider(_query).notifier).loadNextPage();
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
    final assetsAsync = ref.watch(assetsListProvider(_query));
    final profilesAsync = ref.watch(assetProfilesProvider);
    final hasProfileChips =
        profilesAsync.valueOrNull != null &&
        profilesAsync.valueOrNull!.isNotEmpty;
    final topListPadding = hasProfileChips
        ? DesignTokens.spacing4
        : DesignTokens.spacing16;

    final appBar = _isSearching
        ? TbAppSearchBar(
            searchHint: 'Search assets...',
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
            title: const Text('Assets'),
            actions: [
              IconButton(
                tooltip: 'Search assets',
                constraints: const BoxConstraints(
                  minWidth: DesignTokens.minTouchTarget,
                  minHeight: DesignTokens.minTouchTarget,
                ),
                icon: const Icon(Icons.search),
                onPressed: () => setState(() => _isSearching = true),
              ),
            ],
          );

    final listContent = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        profilesAsync.when(
          error: (_, _) => const SizedBox.shrink(),
          loading: () => const SizedBox.shrink(),
          data: (profiles) {
            if (profiles.isEmpty) return const SizedBox.shrink();
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
                    label: const Text('All'),
                    selected: _selectedProfileId == null,
                    onSelected: (_) =>
                        setState(() => _selectedProfileId = null),
                  ),
                  for (final profile in profiles)
                    FilterChip(
                      label: Text(profile.name),
                      selected: _selectedProfileId == profile.id,
                      onSelected: (_) =>
                          setState(() => _selectedProfileId = profile.id),
                    ),
                ],
              ),
            );
          },
        ),
        Expanded(
          child: assetsAsync.when(
            error: (error, _) {
              final failure = error is TbFailure ? error : null;
              final is403 = failure?.type == TbFailureType.permissionDenied;
              return TbEmptyState(
                icon: TbIconKind.assetBuilding,
                title: is403 ? 'Access Restricted' : 'Failed to load assets',
                subtitle: is403
                    ? 'You do not have permission to view assets.'
                    : (failure?.message ?? error.toString()),
                actionLabel: is403 ? null : 'Retry',
                onAction: is403
                    ? null
                    : () => ref
                          .read(assetsListProvider(_query).notifier)
                          .refresh(),
                isError: true,
              );
            },
            loading: () => SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                DesignTokens.spacing16,
                topListPadding,
                DesignTokens.spacing16,
                DesignTokens.bottomScrollPadding(context),
              ),
              child: const TbShimmerList(itemCount: 6),
            ),
            data: (pagedState) {
              if (pagedState.items.isEmpty) {
                final isFiltered =
                    _searchQuery != null || _selectedProfileId != null;
                return TbEmptyState(
                  icon: TbIconKind.assetBuilding,
                  title: isFiltered
                      ? 'No matching assets'
                      : 'No assets available',
                  subtitle: isFiltered
                      ? 'Try adjusting your search or profile filter.'
                      : 'Configured assets will appear here.',
                  actionLabel: isFiltered ? 'Clear filters' : null,
                  onAction: isFiltered
                      ? () => setState(() {
                          _searchQuery = null;
                          _selectedProfileId = null;
                          _isSearching = false;
                        })
                      : null,
                );
              }

              if (isTwoPane &&
                  _selectedAssetId == null &&
                  pagedState.items.isNotEmpty) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted && _selectedAssetId == null) {
                    setState(() {
                      _selectedAssetId = pagedState.items.first.id;
                    });
                  }
                });
              }

              return RefreshIndicator(
                onRefresh: () =>
                    ref.read(assetsListProvider(_query).notifier).refresh(),
                child: ListView.separated(
                  controller: _scrollController,
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: EdgeInsets.fromLTRB(
                    DesignTokens.spacing16,
                    topListPadding,
                    DesignTokens.spacing16,
                    DesignTokens.bottomScrollPadding(context),
                  ),
                  itemCount:
                      pagedState.items.length +
                      (pagedState.isLoadingMore ? 1 : 0),
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

                    final asset = pagedState.items[index];
                    final isSelected =
                        isTwoPane && asset.id == _selectedAssetId;

                    return TbStaggeredEntry(
                      index: index,
                      child: _AssetListCard(
                        asset: asset,
                        isSelected: isSelected,
                        onTap: () {
                          if (isTwoPane) {
                            setState(() {
                              _selectedAssetId = asset.id;
                            });
                          } else {
                            final router = GoRouter.maybeOf(context);
                            if (router != null) {
                              context.push(
                                AppRoutes.assetDetailsPath(asset.id),
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
          ),
        ),
      ],
    );

    return Scaffold(
      appBar: appBar,
      body: SafeArea(
        bottom: false,
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
                    child: _selectedAssetId != null
                        ? AssetDetailsPage(
                            key: ValueKey(_selectedAssetId),
                            assetId: _selectedAssetId!,
                            embedded: true,
                          )
                        : Center(
                            child: Text(
                              'Select an asset to view details',
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

class _AssetListCard extends StatelessWidget {
  const _AssetListCard({
    required this.asset,
    required this.isSelected,
    required this.onTap,
  });

  final TbAssetInfo asset;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Semantics(
      button: true,
      label: 'Asset ${asset.name}',
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
        child: TbListRow(
          title: asset.name,
          meta: [
            asset.type,
            asset.ownerName,
          ].where((s) => s.trim().isNotEmpty).join(' · '),
          leading: TbIcon(
            TbIconKind.assetBuilding,
            size: DesignTokens.iconMedium,
            color: scheme.primary,
          ),
          trailing: Icon(
            Icons.chevron_right,
            color: isSelected ? scheme.primary : scheme.onSurfaceVariant,
          ),
          onTap: onTap,
        ),
      ),
    );
  }
}
