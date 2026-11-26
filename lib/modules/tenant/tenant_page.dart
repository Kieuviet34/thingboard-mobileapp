import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:thingsboard_democloud_app/config/themes/design_tokens.dart';
import 'package:thingsboard_democloud_app/core/api/controllers/auth_controller.dart';
import 'package:thingsboard_democloud_app/core/api/controllers/tenant_controller.dart';
import 'package:thingsboard_democloud_app/core/models/auth_models.dart';
import 'package:thingsboard_democloud_app/core/models/entity_id.dart';
import 'package:thingsboard_democloud_app/core/models/tb_failure.dart';
import 'package:thingsboard_democloud_app/core/models/tenant_models.dart';
import 'package:thingsboard_democloud_app/widgets/icons/tb_icons.dart';
import 'package:thingsboard_democloud_app/widgets/tb_app_bar.dart';
import 'package:thingsboard_democloud_app/widgets/tb_app_search_bar.dart';
import 'package:thingsboard_democloud_app/widgets/tb_empty_state.dart';
import 'package:thingsboard_democloud_app/widgets/tb_metric_pill.dart';
import 'package:thingsboard_democloud_app/widgets/tb_motion.dart';
import 'package:thingsboard_democloud_app/widgets/tb_shimmer.dart';
import 'package:thingsboard_democloud_app/widgets/tb_status_badge.dart';

enum _TenantAdminSection {
  overview('Overview'),
  entityViews('Views'),
  edges('Edges');

  const _TenantAdminSection(this.label);
  final String label;
}

enum _SysAdminSection {
  tenants('Tenants'),
  profiles('Profiles');

  const _SysAdminSection(this.label);
  final String label;
}

/// Role-aware Tenant workspace screen:
/// - `TENANT_ADMIN`: Tenant info + subscription usage, Entity Views, and Edge gateways.
/// - `SYS_ADMIN`: Paginated Tenants CRUD and Tenant Profiles management.
class TenantPage extends ConsumerStatefulWidget {
  const TenantPage({super.key});

  @override
  ConsumerState<TenantPage> createState() => _TenantPageState();
}

class _TenantPageState extends ConsumerState<TenantPage> {
  _TenantAdminSection _tenantSection = _TenantAdminSection.overview;
  _SysAdminSection _sysSection = _SysAdminSection.tenants;
  bool _isSearching = false;
  String? _searchQuery;

  void _handleSearch(String query) {
    final trimmed = query.trim();
    final next = trimmed.isEmpty ? null : trimmed;
    if (next != _searchQuery) {
      setState(() => _searchQuery = next);
    }
  }

  void _closeSearch() {
    setState(() {
      _isSearching = false;
      _searchQuery = null;
    });
  }

  Future<void> _openTenantEditor({
    TbTenantInfo? existing,
    required bool isSysAdmin,
  }) async {
    final titleCtrl = TextEditingController(text: existing?.title ?? '');
    final regionCtrl = TextEditingController(text: existing?.region ?? '');
    final emailCtrl = TextEditingController(text: existing?.email ?? '');
    final phoneCtrl = TextEditingController(text: existing?.phone ?? '');
    final cityCtrl = TextEditingController(text: existing?.city ?? '');
    final countryCtrl = TextEditingController(text: existing?.country ?? '');

    final submitted = await showModalBottomSheet<TbTenantInfo>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetCtx) {
        return Padding(
          padding: EdgeInsets.fromLTRB(
            DesignTokens.spacing20,
            DesignTokens.spacing20,
            DesignTokens.spacing20,
            MediaQuery.viewInsetsOf(sheetCtx).bottom + DesignTokens.spacing20,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  existing == null ? 'New Tenant' : 'Edit Tenant',
                  style: Theme.of(
                    sheetCtx,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: DesignTokens.spacing16),
                TextField(
                  key: const Key('tenant_title_field'),
                  controller: titleCtrl,
                  decoration: const InputDecoration(labelText: 'Title'),
                ),
                const SizedBox(height: DesignTokens.spacing12),
                TextField(
                  key: const Key('tenant_region_field'),
                  controller: regionCtrl,
                  decoration: const InputDecoration(labelText: 'Region'),
                ),
                const SizedBox(height: DesignTokens.spacing12),
                TextField(
                  key: const Key('tenant_email_field'),
                  controller: emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(labelText: 'Email'),
                ),
                const SizedBox(height: DesignTokens.spacing12),
                TextField(
                  key: const Key('tenant_phone_field'),
                  controller: phoneCtrl,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(labelText: 'Phone'),
                ),
                const SizedBox(height: DesignTokens.spacing12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        key: const Key('tenant_city_field'),
                        controller: cityCtrl,
                        decoration: const InputDecoration(labelText: 'City'),
                      ),
                    ),
                    const SizedBox(width: DesignTokens.spacing12),
                    Expanded(
                      child: TextField(
                        key: const Key('tenant_country_field'),
                        controller: countryCtrl,
                        decoration: const InputDecoration(labelText: 'Country'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: DesignTokens.spacing20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(sheetCtx).pop(),
                      child: const Text('Cancel'),
                    ),
                    const SizedBox(width: DesignTokens.spacing8),
                    FilledButton(
                      key: const Key('save_tenant_button'),
                      onPressed: () {
                        final title = titleCtrl.text.trim();
                        if (title.isEmpty) return;
                        final base =
                            existing ?? const TbTenantInfo(id: '', title: '');
                        Navigator.of(sheetCtx).pop(
                          base.copyWith(
                            title: title,
                            region: regionCtrl.text.trim(),
                            email: emailCtrl.text.trim(),
                            phone: phoneCtrl.text.trim(),
                            city: cityCtrl.text.trim(),
                            country: countryCtrl.text.trim(),
                          ),
                        );
                      },
                      child: const Text('Save'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );

    if (submitted == null || !mounted) return;
    try {
      if (isSysAdmin) {
        await ref
            .read(tenantsListProvider(_searchQuery).notifier)
            .saveTenant(submitted);
      } else {
        await ref.read(currentTenantInfoProvider.notifier).save(submitted);
      }
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Tenant saved')));
      }
    } on TbFailure catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider).valueOrNull;
    final authority = authState is AuthAuthenticated
        ? authState.user.authority
        : Authority.unknown;
    final isSysAdmin = authority == Authority.sysAdmin;
    final canAccess = canAccessTenantWorkspace(authority);

    final showSearchAction =
        canAccess &&
        (isSysAdmin || _tenantSection != _TenantAdminSection.overview);

    final appBar = _isSearching
        ? TbAppSearchBar(
            searchHint: 'Search...',
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
            title: Text(isSysAdmin ? 'Tenants' : 'Tenant'),
            actions: [
              if (showSearchAction)
                IconButton(
                  tooltip: 'Search',
                  constraints: const BoxConstraints(
                    minWidth: DesignTokens.minTouchTarget,
                    minHeight: DesignTokens.minTouchTarget,
                  ),
                  icon: const Icon(Icons.search),
                  onPressed: () => setState(() => _isSearching = true),
                ),
            ],
          );

    if (!canAccess) {
      return Scaffold(
        appBar: appBar,
        body: const SafeArea(
          child: TbEmptyState(
            icon: TbIconKind.customerOrg,
            title: 'Access Restricted',
            subtitle: 'Tenant workspace requires Tenant or System Admin role.',
            isError: true,
          ),
        ),
      );
    }

    return Scaffold(
      appBar: appBar,
      floatingActionButton:
          (isSysAdmin && _sysSection == _SysAdminSection.tenants)
          ? FloatingActionButton(
              key: const Key('add_tenant_fab'),
              tooltip: 'New tenant',
              onPressed: () => _openTenantEditor(isSysAdmin: true),
              child: const Icon(Icons.add),
            )
          : null,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: DesignTokens.maxReadableWidth,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    DesignTokens.spacing16,
                    DesignTokens.spacing12,
                    DesignTokens.spacing16,
                    DesignTokens.spacing8,
                  ),
                  child: isSysAdmin
                      ? SegmentedButton<_SysAdminSection>(
                          showSelectedIcon: false,
                          selected: {_sysSection},
                          onSelectionChanged: (s) {
                            if (s.isNotEmpty) {
                              setState(() {
                                _sysSection = s.first;
                                _closeSearch();
                              });
                            }
                          },
                          segments: [
                            for (final tab in _SysAdminSection.values)
                              ButtonSegment<_SysAdminSection>(
                                value: tab,
                                label: Text(tab.label),
                              ),
                          ],
                        )
                      : SegmentedButton<_TenantAdminSection>(
                          showSelectedIcon: false,
                          selected: {_tenantSection},
                          onSelectionChanged: (s) {
                            if (s.isNotEmpty) {
                              setState(() {
                                _tenantSection = s.first;
                                _closeSearch();
                              });
                            }
                          },
                          segments: [
                            for (final tab in _TenantAdminSection.values)
                              ButtonSegment<_TenantAdminSection>(
                                value: tab,
                                label: Text(tab.label),
                              ),
                          ],
                        ),
                ),
                Expanded(
                  child: isSysAdmin
                      ? (_sysSection == _SysAdminSection.tenants
                            ? _SysAdminTenantsList(
                                searchQuery: _searchQuery,
                                onEdit: (t) => _openTenantEditor(
                                  existing: t,
                                  isSysAdmin: true,
                                ),
                              )
                            : _SysAdminProfilesList(searchQuery: _searchQuery))
                      : switch (_tenantSection) {
                          _TenantAdminSection.overview =>
                            _TenantOverviewSection(
                              onEdit: (t) => _openTenantEditor(
                                existing: t,
                                isSysAdmin: false,
                              ),
                            ),
                          _TenantAdminSection.entityViews =>
                            _TenantEntityViewsList(searchQuery: _searchQuery),
                          _TenantAdminSection.edges => _TenantEdgesList(
                            searchQuery: _searchQuery,
                          ),
                        },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TenantOverviewSection extends ConsumerWidget {
  const _TenantOverviewSection({required this.onEdit});

  final ValueChanged<TbTenantInfo> onEdit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final tenantAsync = ref.watch(currentTenantInfoProvider);
    final subAsync = ref.watch(tenantSubscriptionSummaryProvider);
    final homeDashAsync = ref.watch(tenantHomeDashboardProvider);

    return tenantAsync.when(
      loading: () => const SingleChildScrollView(
        padding: DesignTokens.paddingMedium,
        child: TbShimmerList(itemCount: 3),
      ),
      error: (error, _) {
        final failure = error is TbFailure ? error : null;
        final is403 = failure?.type == TbFailureType.permissionDenied;
        return TbEmptyState(
          icon: TbIconKind.customerOrg,
          title: is403 ? 'Access Restricted' : 'Failed to load tenant',
          subtitle: failure?.message,
          actionLabel: is403 ? null : 'Retry',
          onAction: is403
              ? null
              : () => ref.invalidate(currentTenantInfoProvider),
          isError: true,
        );
      },
      data: (tenant) {
        if (tenant == null) {
          return const TbEmptyState(
            icon: TbIconKind.customerOrg,
            title: 'No tenant profile',
          );
        }

        final sub = subAsync.valueOrNull;
        final homeDash = homeDashAsync.valueOrNull;
        final location = tenant.locationSummary;

        return RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(currentTenantInfoProvider);
            ref.invalidate(tenantSubscriptionSummaryProvider);
            ref.invalidate(tenantHomeDashboardProvider);
          },
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(
              DesignTokens.spacing16,
              DesignTokens.spacing8,
              DesignTokens.spacing16,
              84,
            ),
            children: [
              TbStaggeredEntry(
                index: 0,
                child: Container(
                  padding: DesignTokens.cardPadding,
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerLow,
                    borderRadius: DesignTokens.borderRadiusXl,
                    border: Border.all(color: scheme.outlineVariant),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: scheme.primaryContainer,
                              borderRadius: DesignTokens.borderRadiusMedium,
                            ),
                            child: Center(
                              child: TbIcon(
                                TbIconKind.customerOrg,
                                color: scheme.onPrimaryContainer,
                              ),
                            ),
                          ),
                          const SizedBox(width: DesignTokens.spacing12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  tenant.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: DesignTokens.spacing4),
                                Wrap(
                                  spacing: DesignTokens.spacing8,
                                  runSpacing: DesignTokens.spacing4,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: [
                                    TbStatusBadge.online(
                                      tenant.active,
                                      compact: true,
                                    ),
                                    if (tenant.tenantProfileName.isNotEmpty)
                                      _MetaChip(
                                        label: tenant.tenantProfileName,
                                      ),
                                    if (tenant.region.isNotEmpty)
                                      _MetaChip(label: tenant.region),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            key: const Key('edit_tenant_button'),
                            tooltip: 'Edit tenant',
                            constraints: const BoxConstraints(
                              minWidth: DesignTokens.minTouchTarget,
                              minHeight: DesignTokens.minTouchTarget,
                            ),
                            icon: const Icon(Icons.edit_outlined),
                            onPressed: () => onEdit(tenant),
                          ),
                        ],
                      ),
                      if (location.isNotEmpty ||
                          tenant.email.isNotEmpty ||
                          tenant.phone.isNotEmpty) ...[
                        const SizedBox(height: DesignTokens.spacing16),
                        Wrap(
                          spacing: DesignTokens.spacing12,
                          runSpacing: DesignTokens.spacing8,
                          children: [
                            if (location.isNotEmpty)
                              _IconValuePair(
                                icon: Icons.place_outlined,
                                value: location,
                              ),
                            if (tenant.email.isNotEmpty)
                              _IconValuePair(
                                icon: Icons.alternate_email_rounded,
                                value: tenant.email,
                              ),
                            if (tenant.phone.isNotEmpty)
                              _IconValuePair(
                                icon: Icons.phone_outlined,
                                value: tenant.phone,
                              ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              if (sub != null) ...[
                const SizedBox(height: DesignTokens.spacing12),
                TbStaggeredEntry(
                  index: 1,
                  child: Container(
                    padding: DesignTokens.cardPadding,
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerLow,
                      borderRadius: DesignTokens.borderRadiusXl,
                      border: Border.all(color: scheme.outlineVariant),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              sub.planName ?? 'Subscription',
                              style: textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            if (sub.state != null && sub.state!.isNotEmpty)
                              _MetaChip(label: sub.state!),
                          ],
                        ),
                        if (sub.usage.isNotEmpty) ...[
                          const SizedBox(height: DesignTokens.spacing12),
                          Wrap(
                            spacing: DesignTokens.spacing16,
                            runSpacing: DesignTokens.spacing12,
                            children: [
                              if (sub.usage['devices'] != null)
                                TbMetricPill(
                                  icon: TbIconKind.sensorNode,
                                  label: 'Devices',
                                  value: sub.usage['maxDevices'] != null
                                      ? '${sub.usage['devices']}/${sub.usage['maxDevices']}'
                                      : '${sub.usage['devices']}',
                                ),
                              if (sub.usage['assets'] != null)
                                TbMetricPill(
                                  icon: TbIconKind.assetBuilding,
                                  label: 'Assets',
                                  value: sub.usage['maxAssets'] != null
                                      ? '${sub.usage['assets']}/${sub.usage['maxAssets']}'
                                      : '${sub.usage['assets']}',
                                ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
              if (homeDash?.dashboardId != null) ...[
                const SizedBox(height: DesignTokens.spacing12),
                TbStaggeredEntry(
                  index: 2,
                  child: Container(
                    padding: DesignTokens.cardPadding,
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerLow,
                      borderRadius: DesignTokens.borderRadiusLarge,
                      border: Border.all(color: scheme.outlineVariant),
                    ),
                    child: Row(
                      children: [
                        TbIcon(TbIconKind.dashboardTile, color: scheme.primary),
                        const SizedBox(width: DesignTokens.spacing12),
                        Expanded(
                          child: Text(
                            'Home: ${homeDash!.dashboardId}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        _MetaChip(
                          label: homeDash.hideDashboardToolbar
                              ? 'Clean'
                              : 'Toolbar',
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _TenantEntityViewsList extends ConsumerWidget {
  const _TenantEntityViewsList({required this.searchQuery});

  final String? searchQuery;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final viewsAsync = ref.watch(tenantEntityViewsProvider(searchQuery));

    return viewsAsync.when(
      loading: () => const SingleChildScrollView(
        padding: DesignTokens.paddingMedium,
        child: TbShimmerList(itemCount: 4),
      ),
      error: (err, _) => TbEmptyState(
        icon: TbIconKind.relationsGraph,
        title: 'Failed to load views',
        subtitle: err is TbFailure ? err.message : null,
        actionLabel: 'Retry',
        isError: true,
        onAction: () =>
            ref.read(tenantEntityViewsProvider(searchQuery).notifier).refresh(),
      ),
      data: (paged) {
        if (paged.items.isEmpty) {
          return const TbEmptyState(
            icon: TbIconKind.relationsGraph,
            title: 'No entity views',
          );
        }
        return RefreshIndicator(
          onRefresh: () => ref
              .read(tenantEntityViewsProvider(searchQuery).notifier)
              .refresh(),
          child: ListView.separated(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(
              DesignTokens.spacing16,
              DesignTokens.spacing8,
              DesignTokens.spacing16,
              84,
            ),
            itemCount: paged.items.length,
            separatorBuilder: (_, _) =>
                const SizedBox(height: DesignTokens.spacing8),
            itemBuilder: (context, index) {
              final view = paged.items[index];
              return TbStaggeredEntry(
                index: index,
                child: Container(
                  padding: DesignTokens.cardPadding,
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerLow,
                    borderRadius: DesignTokens.borderRadiusLarge,
                    border: Border.all(color: scheme.outlineVariant),
                  ),
                  child: Row(
                    children: [
                      TbIcon(TbIconKind.relationsGraph, color: scheme.primary),
                      const SizedBox(width: DesignTokens.spacing12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              view.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: DesignTokens.spacing4),
                            Wrap(
                              spacing: DesignTokens.spacing8,
                              children: [
                                if (view.type.isNotEmpty)
                                  _MetaChip(label: view.type),
                                if (view.ownerName.isNotEmpty)
                                  Text(
                                    view.ownerName,
                                    style: textTheme.bodySmall?.copyWith(
                                      color: scheme.onSurfaceVariant,
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}

class _TenantEdgesList extends ConsumerWidget {
  const _TenantEdgesList({required this.searchQuery});

  final String? searchQuery;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final edgesAsync = ref.watch(tenantEdgesProvider(searchQuery));

    return edgesAsync.when(
      loading: () => const SingleChildScrollView(
        padding: DesignTokens.paddingMedium,
        child: TbShimmerList(itemCount: 4),
      ),
      error: (err, _) => TbEmptyState(
        icon: TbIconKind.gateway,
        title: 'Failed to load edges',
        subtitle: err is TbFailure ? err.message : null,
        actionLabel: 'Retry',
        isError: true,
        onAction: () =>
            ref.read(tenantEdgesProvider(searchQuery).notifier).refresh(),
      ),
      data: (paged) {
        if (paged.items.isEmpty) {
          return const TbEmptyState(
            icon: TbIconKind.gateway,
            title: 'No edge instances',
          );
        }
        return RefreshIndicator(
          onRefresh: () =>
              ref.read(tenantEdgesProvider(searchQuery).notifier).refresh(),
          child: ListView.separated(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(
              DesignTokens.spacing16,
              DesignTokens.spacing8,
              DesignTokens.spacing16,
              84,
            ),
            itemCount: paged.items.length,
            separatorBuilder: (_, _) =>
                const SizedBox(height: DesignTokens.spacing8),
            itemBuilder: (context, index) {
              final edge = paged.items[index];
              return TbStaggeredEntry(
                index: index,
                child: Container(
                  padding: DesignTokens.cardPadding,
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerLow,
                    borderRadius: DesignTokens.borderRadiusLarge,
                    border: Border.all(color: scheme.outlineVariant),
                  ),
                  child: Row(
                    children: [
                      TbIcon(TbIconKind.gateway, color: scheme.primary),
                      const SizedBox(width: DesignTokens.spacing12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              edge.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: DesignTokens.spacing4),
                            Wrap(
                              spacing: DesignTokens.spacing8,
                              children: [
                                if (edge.type.isNotEmpty)
                                  _MetaChip(label: edge.type),
                                if (edge.label.isNotEmpty)
                                  Text(
                                    edge.label,
                                    style: textTheme.bodySmall?.copyWith(
                                      color: scheme.onSurfaceVariant,
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}

class _SysAdminTenantsList extends ConsumerWidget {
  const _SysAdminTenantsList({required this.searchQuery, required this.onEdit});

  final String? searchQuery;
  final ValueChanged<TbTenantInfo> onEdit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final tenantsAsync = ref.watch(tenantsListProvider(searchQuery));

    return tenantsAsync.when(
      loading: () => const SingleChildScrollView(
        padding: DesignTokens.paddingMedium,
        child: TbShimmerList(itemCount: 4),
      ),
      error: (err, _) => TbEmptyState(
        icon: TbIconKind.customerOrg,
        title: 'Failed to load tenants',
        subtitle: err is TbFailure ? err.message : null,
        actionLabel: 'Retry',
        isError: true,
        onAction: () =>
            ref.read(tenantsListProvider(searchQuery).notifier).refresh(),
      ),
      data: (paged) {
        if (paged.items.isEmpty) {
          return const TbEmptyState(
            icon: TbIconKind.customerOrg,
            title: 'No tenants',
          );
        }
        return RefreshIndicator(
          onRefresh: () =>
              ref.read(tenantsListProvider(searchQuery).notifier).refresh(),
          child: ListView.separated(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(
              DesignTokens.spacing16,
              DesignTokens.spacing8,
              DesignTokens.spacing16,
              84,
            ),
            itemCount: paged.items.length,
            separatorBuilder: (_, _) =>
                const SizedBox(height: DesignTokens.spacing8),
            itemBuilder: (context, index) {
              final tenant = paged.items[index];
              return TbStaggeredEntry(
                index: index,
                child: Material(
                  color: scheme.surfaceContainerLow,
                  shape: RoundedRectangleBorder(
                    borderRadius: DesignTokens.borderRadiusLarge,
                    side: BorderSide(color: scheme.outlineVariant),
                  ),
                  child: InkWell(
                    borderRadius: DesignTokens.borderRadiusLarge,
                    onTap: () => onEdit(tenant),
                    child: Padding(
                      padding: DesignTokens.cardPadding,
                      child: Row(
                        children: [
                          TbIcon(TbIconKind.customerOrg, color: scheme.primary),
                          const SizedBox(width: DesignTokens.spacing12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  tenant.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: DesignTokens.spacing4),
                                Wrap(
                                  spacing: DesignTokens.spacing8,
                                  children: [
                                    _MetaChip(label: tenant.tenantProfileName),
                                    if (tenant.email.isNotEmpty)
                                      Text(
                                        tenant.email,
                                        style: textTheme.bodySmall?.copyWith(
                                          color: scheme.onSurfaceVariant,
                                        ),
                                      ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            tooltip: 'Delete tenant',
                            constraints: const BoxConstraints(
                              minWidth: DesignTokens.minTouchTarget,
                              minHeight: DesignTokens.minTouchTarget,
                            ),
                            icon: Icon(
                              Icons.delete_outline,
                              color: scheme.error,
                            ),
                            onPressed: () async {
                              await ref
                                  .read(
                                    tenantsListProvider(searchQuery).notifier,
                                  )
                                  .deleteTenant(tenant.id);
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}

class _SysAdminProfilesList extends ConsumerWidget {
  const _SysAdminProfilesList({required this.searchQuery});

  final String? searchQuery;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final profilesAsync = ref.watch(tenantProfilesListProvider(searchQuery));

    return profilesAsync.when(
      loading: () => const SingleChildScrollView(
        padding: DesignTokens.paddingMedium,
        child: TbShimmerList(itemCount: 4),
      ),
      error: (err, _) => TbEmptyState(
        icon: TbIconKind.attributesTag,
        title: 'Failed to load profiles',
        subtitle: err is TbFailure ? err.message : null,
        actionLabel: 'Retry',
        isError: true,
        onAction: () => ref
            .read(tenantProfilesListProvider(searchQuery).notifier)
            .refresh(),
      ),
      data: (paged) {
        if (paged.items.isEmpty) {
          return const TbEmptyState(
            icon: TbIconKind.attributesTag,
            title: 'No tenant profiles',
          );
        }
        return RefreshIndicator(
          onRefresh: () => ref
              .read(tenantProfilesListProvider(searchQuery).notifier)
              .refresh(),
          child: ListView.separated(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(
              DesignTokens.spacing16,
              DesignTokens.spacing8,
              DesignTokens.spacing16,
              84,
            ),
            itemCount: paged.items.length,
            separatorBuilder: (_, _) =>
                const SizedBox(height: DesignTokens.spacing8),
            itemBuilder: (context, index) {
              final profile = paged.items[index];
              return TbStaggeredEntry(
                index: index,
                child: Container(
                  padding: DesignTokens.cardPadding,
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerLow,
                    borderRadius: DesignTokens.borderRadiusLarge,
                    border: Border.all(color: scheme.outlineVariant),
                  ),
                  child: Row(
                    children: [
                      TbIcon(TbIconKind.attributesTag, color: scheme.primary),
                      const SizedBox(width: DesignTokens.spacing12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              profile.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            if (profile.description.isNotEmpty) ...[
                              const SizedBox(height: DesignTokens.spacing4),
                              Text(
                                profile.description,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: textTheme.bodySmall?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      if (profile.isDefault)
                        const _MetaChip(label: 'Default')
                      else
                        TextButton(
                          onPressed: () => ref
                              .read(
                                tenantProfilesListProvider(
                                  searchQuery,
                                ).notifier,
                              )
                              .setDefault(profile.id),
                          child: const Text('Set default'),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: DesignTokens.spacing8,
        vertical: DesignTokens.spacing2,
      ),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: DesignTokens.borderRadiusRound,
      ),
      child: Text(
        label,
        style: textTheme.labelSmall?.copyWith(
          color: scheme.onSurfaceVariant,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _IconValuePair extends StatelessWidget {
  const _IconValuePair({required this.icon, required this.value});

  final IconData icon;
  final String value;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          size: DesignTokens.iconSmall,
          color: scheme.onSurfaceVariant,
        ),
        const SizedBox(width: DesignTokens.spacing4),
        Flexible(
          child: Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}
