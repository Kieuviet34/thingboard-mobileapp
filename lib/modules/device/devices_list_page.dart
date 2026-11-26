import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:thingsboard_democloud_app/config/routes/router.dart';
import 'package:thingsboard_democloud_app/config/themes/design_tokens.dart';
import 'package:thingsboard_democloud_app/config/themes/tb_text_styles.dart';
import 'package:thingsboard_democloud_app/core/api/controllers/device_controller.dart';
import 'package:thingsboard_democloud_app/core/models/device_models.dart';
import 'package:thingsboard_democloud_app/core/models/tb_failure.dart';
import 'package:thingsboard_democloud_app/modules/device/device_details_page.dart';
import 'package:thingsboard_democloud_app/widgets/icons/tb_icons.dart';
import 'package:thingsboard_democloud_app/widgets/tb_app_bar.dart';
import 'package:thingsboard_democloud_app/widgets/tb_app_search_bar.dart';
import 'package:thingsboard_democloud_app/widgets/tb_empty_state.dart';
import 'package:thingsboard_democloud_app/widgets/tb_list_row.dart';
import 'package:thingsboard_democloud_app/widgets/tb_metric_pill.dart';
import 'package:thingsboard_democloud_app/widgets/tb_motion.dart';
import 'package:thingsboard_democloud_app/widgets/tb_shimmer.dart';
import 'package:thingsboard_democloud_app/widgets/tb_status_badge.dart';

/// Material 3 Devices list with profile filter, Online/Offline FilterChips,
/// debounced search, pagination, <=3-line telemetry rows, and >=840dp 2-pane layout.
class DevicesListPage extends ConsumerStatefulWidget {
  const DevicesListPage({
    super.key,
    this.deviceProfileId,
    this.deviceType,
    this.active,
    this.searchMode = false,
    this.initialSelectedDeviceId,
  });

  final String? deviceProfileId;
  final String? deviceType;
  final bool? active;
  final bool searchMode;
  final String? initialSelectedDeviceId;

  @override
  ConsumerState<DevicesListPage> createState() => _DevicesListPageState();
}

class _DevicesListPageState extends ConsumerState<DevicesListPage> {
  final ScrollController _scrollController = ScrollController();
  late bool _isSearching;
  late String? _profileId;
  late String? _profileTitle;
  late bool? _activeFilter;
  String _searchText = '';
  String? _selectedDeviceId;

  @override
  void initState() {
    super.initState();
    _isSearching = widget.searchMode;
    _profileId = widget.deviceProfileId;
    _profileTitle = widget.deviceType;
    _activeFilter = widget.active;
    _selectedDeviceId = widget.initialSelectedDeviceId;
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  TbDeviceQuery get _query => TbDeviceQuery(
    deviceProfileId: _profileId,
    deviceType: _profileTitle,
    active: _activeFilter,
    textSearch: _searchText.isEmpty ? null : _searchText,
  );

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;
    if (pos.pixels >= pos.maxScrollExtent - 240) {
      ref.read(devicesListProvider(_query).notifier).loadNextPage();
    }
  }

  void _clearFilters() {
    setState(() {
      _profileId = null;
      _profileTitle = null;
      _activeFilter = null;
      _searchText = '';
    });
  }

  void _openDevice(TbDeviceInfo device, {required bool useTwoPane}) {
    if (useTwoPane) {
      setState(() => _selectedDeviceId = device.id);
      return;
    }
    GoRouter.maybeOf(context)?.push(AppRoutes.deviceDetailsPath(device.id));
  }

  @override
  Widget build(BuildContext context) {
    final query = _query;
    final devicesAsync = ref.watch(devicesListProvider(query));
    final width = MediaQuery.sizeOf(context).width;
    final useTwoPane = width >= DesignTokens.mediumMaxWidth;
    final scheme = Theme.of(context).colorScheme;

    final hasFilters =
        _profileId != null ||
        _profileTitle != null ||
        _activeFilter != null ||
        _searchText.isNotEmpty;

    final PreferredSizeWidget appBar = _isSearching
        ? TbAppSearchBar(
            searchHint: 'Search devices',
            leading: IconButton(
              key: const Key('devices-search-close-button'),
              tooltip: 'Close search',
              constraints: const BoxConstraints(
                minWidth: DesignTokens.minTouchTarget,
                minHeight: DesignTokens.minTouchTarget,
              ),
              icon: const Icon(Icons.arrow_back),
              onPressed: () {
                setState(() {
                  _searchText = '';
                  _isSearching = false;
                });
                if (widget.searchMode) {
                  GoRouter.maybeOf(context)?.pop();
                }
              },
            ),
            onSearch: (q) => setState(() => _searchText = q.trim()),
          )
        : TbAppBar(
            title: Text(
              _profileTitle != null && _profileTitle!.isNotEmpty
                  ? _profileTitle!
                  : 'Devices',
            ),
            actions: [
              IconButton(
                key: const Key('devices-list-search-toggle'),
                tooltip: 'Search devices',
                constraints: const BoxConstraints(
                  minWidth: DesignTokens.minTouchTarget,
                  minHeight: DesignTokens.minTouchTarget,
                ),
                icon: const Icon(Icons.search),
                onPressed: () => setState(() => _isSearching = true),
              ),
            ],
          );

    final filterBar = SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(
        horizontal: DesignTokens.spacing16,
        vertical: DesignTokens.spacing8,
      ),
      child: Row(
        spacing: DesignTokens.spacing8,
        children: [
          FilterChip(
            key: const Key('device-filter-all'),
            label: const Text('All'),
            selected: _activeFilter == null,
            onSelected: (_) => setState(() => _activeFilter = null),
          ),
          FilterChip(
            key: const Key('device-filter-online'),
            avatar: const TbIcon(
              TbIconKind.livePulse,
              size: DesignTokens.iconXs,
            ),
            label: const Text('Online'),
            selected: _activeFilter == true,
            onSelected: (selected) =>
                setState(() => _activeFilter = selected ? true : null),
          ),
          FilterChip(
            key: const Key('device-filter-offline'),
            avatar: const TbIcon(
              TbIconKind.offlineNode,
              size: DesignTokens.iconXs,
            ),
            label: const Text('Offline'),
            selected: _activeFilter == false,
            onSelected: (selected) =>
                setState(() => _activeFilter = selected ? false : null),
          ),
          if (_profileId != null || _profileTitle != null)
            InputChip(
              key: const Key('device-profile-filter-chip'),
              label: Text(_profileTitle ?? _profileId!),
              onDeleted: () => setState(() {
                _profileId = null;
                _profileTitle = null;
              }),
            ),
        ],
      ),
    );

    final listBody = devicesAsync.when(
      loading: () => const SingleChildScrollView(
        padding: DesignTokens.paddingMedium,
        child: TbShimmerList(itemCount: 5),
      ),
      error: (err, _) => TbEmptyState(
        icon: TbIconKind.severityCritical,
        title: 'Failed to load devices',
        subtitle: err is TbFailure ? err.message : err.toString(),
        isError: true,
        actionLabel: 'Retry',
        onAction: () => ref.read(devicesListProvider(query).notifier).refresh(),
      ),
      data: (paged) {
        if (paged.items.isEmpty) {
          return TbEmptyState(
            icon: TbIconKind.navDevices,
            title: 'No devices found',
            subtitle: hasFilters ? 'Try clearing filters' : null,
            actionLabel: hasFilters ? 'Clear filters' : 'Refresh',
            onAction: hasFilters
                ? _clearFilters
                : () => ref.read(devicesListProvider(query).notifier).refresh(),
          );
        }

        final effectiveSelectedId = useTwoPane
            ? (_selectedDeviceId != null &&
                      paged.items.any((d) => d.id == _selectedDeviceId)
                  ? _selectedDeviceId
                  : paged.items.first.id)
            : _selectedDeviceId;

        final listView = RefreshIndicator(
          onRefresh: () =>
              ref.read(devicesListProvider(query).notifier).refresh(),
          child: ListView.builder(
            controller: _scrollController,
            padding: EdgeInsets.fromLTRB(
              DesignTokens.spacing16,
              DesignTokens.spacing4,
              DesignTokens.spacing16,
              useTwoPane ? DesignTokens.spacing20 : 84.0,
            ),
            itemCount: paged.items.length + (paged.hasNext ? 1 : 0),
            itemBuilder: (context, index) {
              if (index >= paged.items.length) {
                return Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: DesignTokens.spacing12,
                  ),
                  child: Center(
                    child: paged.loadMoreError != null
                        ? TextButton(
                            onPressed: () => ref
                                .read(devicesListProvider(query).notifier)
                                .loadNextPage(),
                            child: const Text('Retry loading more'),
                          )
                        : const TbShimmer(width: 140, height: 18),
                  ),
                );
              }
              final device = paged.items[index];
              final isSelected = useTwoPane && effectiveSelectedId == device.id;
              return Padding(
                padding: const EdgeInsets.only(bottom: DesignTokens.spacing8),
                child: TbStaggeredEntry(
                  index: index,
                  child: _DeviceListRow(
                    device: device,
                    selected: isSelected,
                    enableHero: !useTwoPane,
                    onTap: () => _openDevice(device, useTwoPane: useTwoPane),
                  ),
                ),
              );
            },
          ),
        );

        if (!useTwoPane) return listView;

        return Row(
          children: [
            Expanded(flex: 4, child: listView),
            VerticalDivider(
              width: 1,
              thickness: 1,
              color: scheme.outlineVariant,
            ),
            Expanded(
              flex: 6,
              child: effectiveSelectedId != null
                  ? DeviceDetailsPage(
                      key: ValueKey<String>('pane-device-$effectiveSelectedId'),
                      deviceId: effectiveSelectedId,
                      embedded: true,
                    )
                  : const TbEmptyState(
                      icon: TbIconKind.navDevices,
                      title: 'Select a device',
                    ),
            ),
          ],
        );
      },
    );

    return Scaffold(
      appBar: appBar,
      body: Column(
        children: [
          filterBar,
          Expanded(child: listBody),
        ],
      ),
    );
  }
}

class _DeviceListRow extends StatelessWidget {
  const _DeviceListRow({
    required this.device,
    required this.selected,
    required this.enableHero,
    required this.onTap,
  });

  final TbDeviceInfo device;
  final bool selected;
  final bool enableHero;
  final VoidCallback onTap;

  String _relativeTime(int epochMs) {
    if (epochMs <= 0) return '';
    final diff = DateTime.now().difference(
      DateTime.fromMillisecondsSinceEpoch(epochMs),
    );
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final iconKind = TbIcons.kindForDeviceType(device.type);
    final telemetryEntries = device.telemetry.entries.take(3).toList();
    final subtitleParts = <String>[
      if (device.type.isNotEmpty) device.type,
      if (device.label.isNotEmpty) device.label,
      if (device.label.isEmpty && device.ownerName.isNotEmpty) device.ownerName,
    ];

    final iconBox = Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: scheme.secondaryContainer,
        borderRadius: DesignTokens.borderRadiusMedium,
      ),
      alignment: Alignment.center,
      child: TbIcon(
        iconKind,
        size: DesignTokens.iconMedium,
        color: scheme.onSecondaryContainer,
        semanticLabel: device.type,
      ),
    );

    final heroOrIcon = enableHero
        ? Hero(tag: 'device-${device.id}', child: iconBox)
        : iconBox;

    return Material(
      key: Key('device-row-${device.id}'),
      color: selected
          ? scheme.primaryContainer.withValues(alpha: 0.45)
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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TbListRow(
              title: device.name,
              meta: subtitleParts.join(' · '),
              leading: heroOrIcon,
              trailing: TbStatusBadge.online(device.active, compact: true),
            ),
            if (telemetryEntries.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  DesignTokens.spacing16,
                  0,
                  DesignTokens.spacing16,
                  DesignTokens.spacing12,
                ),
                child: Wrap(
                  spacing: DesignTokens.spacing8,
                  runSpacing: DesignTokens.spacing8,
                  children: [
                    for (final entry in telemetryEntries)
                      TbMetricPill(
                        icon: TbIcons.kindForTelemetryKey(entry.key),
                        value: entry.value,
                      ),
                  ],
                ),
              )
            else if (device.createdTime > 0)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  DesignTokens.spacing16,
                  0,
                  DesignTokens.spacing16,
                  DesignTokens.spacing12,
                ),
                child: Text(
                  _relativeTime(device.createdTime),
                  style: TbTextStyles.tabular(
                    textTheme.labelSmall ?? TbTextStyles.labelSmall,
                  ).copyWith(color: scheme.onSurfaceVariant),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
