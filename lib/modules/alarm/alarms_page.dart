import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:thingsboard_democloud_app/config/routes/router.dart';
import 'package:thingsboard_democloud_app/config/themes/design_tokens.dart';
import 'package:thingsboard_democloud_app/config/themes/tb_status_colors.dart';
import 'package:thingsboard_democloud_app/config/themes/tb_text_styles.dart';
import 'package:thingsboard_democloud_app/core/api/controllers/alarm_controller.dart';
import 'package:thingsboard_democloud_app/core/models/alarm_models.dart';
import 'package:thingsboard_democloud_app/core/models/entity_id.dart';
import 'package:thingsboard_democloud_app/core/models/tb_failure.dart';
import 'package:thingsboard_democloud_app/modules/alarm/alarm_details_page.dart';
import 'package:thingsboard_democloud_app/modules/alarm/widgets/user_info_avatar_widget.dart';
import 'package:thingsboard_democloud_app/widgets/icons/tb_icons.dart';
import 'package:thingsboard_democloud_app/widgets/tb_app_bar.dart';
import 'package:thingsboard_democloud_app/widgets/tb_app_search_bar.dart';
import 'package:thingsboard_democloud_app/widgets/tb_empty_state.dart';
import 'package:thingsboard_democloud_app/widgets/tb_motion.dart';
import 'package:thingsboard_democloud_app/widgets/tb_shimmer.dart';
import 'package:thingsboard_democloud_app/widgets/tb_status_badge.dart';

/// Material 3 Alarms list with debounced search, status/severity FilterChips,
/// quick Ack/Clear actions, pagination, and adaptive 2-pane master-detail (>=840dp).
class AlarmsPage extends ConsumerStatefulWidget {
  const AlarmsPage({
    super.key,
    this.searchMode = false,
    this.originatorId,
    this.initialSelectedAlarmId,
  });

  final bool searchMode;
  final EntityId? originatorId;
  final String? initialSelectedAlarmId;

  @override
  ConsumerState<AlarmsPage> createState() => _AlarmsPageState();
}

class _AlarmsPageState extends ConsumerState<AlarmsPage> {
  final ScrollController _scrollController = ScrollController();
  late bool _isSearching;
  String? _selectedAlarmId;

  @override
  void initState() {
    super.initState();
    _isSearching = widget.searchMode;
    _selectedAlarmId = widget.initialSelectedAlarmId;
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;
    if (pos.pixels >= pos.maxScrollExtent - 240) {
      ref.read(alarmsListProvider(widget.originatorId).notifier).loadNextPage();
    }
  }

  void _updateFilter(TbAlarmFilter Function(TbAlarmFilter current) transform) {
    final current = ref.read(alarmFilterProvider);
    ref.read(alarmFilterProvider.notifier).state = transform(current);
  }

  void _toggleStatus(AlarmSearchStatus status) {
    _updateFilter((current) {
      final next = Set<AlarmSearchStatus>.from(current.statusList);
      if (!next.remove(status)) {
        next.add(status);
      }
      return current.copyWith(statusList: next);
    });
  }

  void _toggleSeverity(AlarmSeverity severity) {
    _updateFilter((current) {
      final next = Set<AlarmSeverity>.from(current.severityList);
      if (!next.remove(severity)) {
        next.add(severity);
      }
      return current.copyWith(severityList: next);
    });
  }

  void _clearAllFilters() {
    ref.read(alarmFilterProvider.notifier).state = const TbAlarmFilter();
  }

  Future<void> _quickAck(String alarmId) async {
    try {
      await ref
          .read(alarmsListProvider(widget.originatorId).notifier)
          .acknowledge(alarmId);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('Alarm acknowledged')));
    } catch (e) {
      if (!mounted) return;
      final msg = e is TbFailure ? e.message : e.toString();
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  Future<void> _quickClear(String alarmId) async {
    try {
      await ref
          .read(alarmsListProvider(widget.originatorId).notifier)
          .clear(alarmId);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('Alarm cleared')));
    } catch (e) {
      if (!mounted) return;
      final msg = e is TbFailure ? e.message : e.toString();
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  void _openAlarm(TbAlarmInfo alarm, {required bool useTwoPane}) {
    if (useTwoPane) {
      setState(() => _selectedAlarmId = alarm.id);
      return;
    }
    final router = GoRouter.maybeOf(context);
    router?.push(AppRoutes.alarmDetailsPath(alarm.id));
  }

  @override
  Widget build(BuildContext context) {
    final filter = ref.watch(alarmFilterProvider);
    final alarmsAsync = ref.watch(alarmsListProvider(widget.originatorId));
    final width = MediaQuery.sizeOf(context).width;
    final useTwoPane = width >= DesignTokens.mediumMaxWidth;
    final scheme = Theme.of(context).colorScheme;

    final hasFilters =
        filter.statusList.isNotEmpty ||
        filter.severityList.isNotEmpty ||
        (filter.textSearch != null && filter.textSearch!.isNotEmpty);

    final PreferredSizeWidget appBar = _isSearching
        ? TbAppSearchBar(
            searchHint: 'Search alarms',
            leading: IconButton(
              key: const Key('alarms-search-close-button'),
              tooltip: 'Close search',
              constraints: const BoxConstraints(
                minWidth: DesignTokens.minTouchTarget,
                minHeight: DesignTokens.minTouchTarget,
              ),
              icon: const Icon(Icons.arrow_back),
              onPressed: () {
                _updateFilter((f) => f.copyWith(clearTextSearch: true));
                if (widget.searchMode) {
                  GoRouter.maybeOf(context)?.pop();
                } else {
                  setState(() => _isSearching = false);
                }
              },
            ),
            onSearch: (q) {
              final trimmed = q.trim();
              _updateFilter(
                (f) => trimmed.isEmpty
                    ? f.copyWith(clearTextSearch: true)
                    : f.copyWith(textSearch: trimmed),
              );
            },
          )
        : TbAppBar(
            canGoBack: widget.originatorId != null,
            title: const Text('Alarms'),
            actions: [
              IconButton(
                key: const Key('alarms-search-toggle-button'),
                tooltip: 'Search alarms',
                constraints: const BoxConstraints(
                  minWidth: DesignTokens.minTouchTarget,
                  minHeight: DesignTokens.minTouchTarget,
                ),
                icon: const Icon(Icons.search),
                onPressed: () => setState(() => _isSearching = true),
              ),
            ],
          );

    final filterStrip = widget.originatorId != null
        ? const SizedBox.shrink()
        : SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(
              horizontal: DesignTokens.spacing16,
              vertical: DesignTokens.spacing8,
            ),
            child: Row(
              spacing: DesignTokens.spacing8,
              children: [
                for (final status in const [
                  AlarmSearchStatus.active,
                  AlarmSearchStatus.unack,
                  AlarmSearchStatus.ack,
                  AlarmSearchStatus.cleared,
                ])
                  FilterChip(
                    key: Key('alarm-status-chip-${status.wireValue}'),
                    label: Text(status.label),
                    selected: filter.statusList.contains(status),
                    onSelected: (_) => _toggleStatus(status),
                  ),
                for (final severity in AlarmSeverity.values)
                  FilterChip(
                    key: Key('alarm-severity-chip-${severity.wireValue}'),
                    avatar: TbIcon(
                      TbIcons.kindForSeverity(severity),
                      size: DesignTokens.iconXs,
                    ),
                    label: Text(severity.label),
                    selected: filter.severityList.contains(severity),
                    onSelected: (_) => _toggleSeverity(severity),
                  ),
                if (hasFilters)
                  ActionChip(
                    key: const Key('alarm-clear-filters-chip'),
                    label: const Text('Reset'),
                    onPressed: _clearAllFilters,
                  ),
              ],
            ),
          );

    final listContent = alarmsAsync.when(
      loading: () => const SingleChildScrollView(
        padding: DesignTokens.paddingMedium,
        child: TbShimmerList(itemCount: 5),
      ),
      error: (err, _) {
        final failure = err is TbFailure ? err : null;
        final is403 = failure?.type == TbFailureType.permissionDenied;
        return TbEmptyState(
          icon: TbIconKind.severityCritical,
          title: is403 ? 'Access Restricted' : 'Failed to load alarms',
          subtitle: is403
              ? 'You do not have permission to view alarms.'
              : (err is TbFailure ? err.message : err.toString()),
          isError: true,
          actionLabel: is403 ? null : 'Retry',
          onAction: is403
              ? null
              : () => ref
                    .read(alarmsListProvider(widget.originatorId).notifier)
                    .refresh(),
        );
      },
      data: (paged) {
        if (paged.items.isEmpty) {
          return TbEmptyState(
            icon: TbIconKind.statusCleared,
            title: 'No alarms',
            subtitle: hasFilters
                ? 'Adjust filters to see alarms'
                : 'All systems nominal',
            actionLabel: hasFilters ? 'Clear filters' : 'Refresh',
            onAction: hasFilters
                ? _clearAllFilters
                : () => ref
                      .read(alarmsListProvider(widget.originatorId).notifier)
                      .refresh(),
          );
        }

        final effectiveSelectedId = useTwoPane
            ? (_selectedAlarmId != null &&
                      paged.items.any((a) => a.id == _selectedAlarmId)
                  ? _selectedAlarmId
                  : paged.items.first.id)
            : _selectedAlarmId;

        final listView = RefreshIndicator(
          onRefresh: () => ref
              .read(alarmsListProvider(widget.originatorId).notifier)
              .refresh(),
          child: ListView.builder(
            controller: _scrollController,
            padding: const EdgeInsets.fromLTRB(
              DesignTokens.spacing16,
              DesignTokens.spacing4,
              DesignTokens.spacing16,
              84.0,
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
                                .read(
                                  alarmsListProvider(
                                    widget.originatorId,
                                  ).notifier,
                                )
                                .loadNextPage(),
                            child: const Text('Retry loading more'),
                          )
                        : const TbShimmer(width: 140, height: 18),
                  ),
                );
              }
              final alarm = paged.items[index];
              final isSelected = useTwoPane && effectiveSelectedId == alarm.id;
              return Padding(
                padding: const EdgeInsets.only(bottom: DesignTokens.spacing8),
                child: TbStaggeredEntry(
                  index: index,
                  child: _AlarmRowCard(
                    alarm: alarm,
                    selected: isSelected,
                    enableHero: !useTwoPane,
                    onTap: () => _openAlarm(alarm, useTwoPane: useTwoPane),
                    onAck: alarm.acknowledged
                        ? null
                        : () => _quickAck(alarm.id),
                    onClear: alarm.cleared ? null : () => _quickClear(alarm.id),
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
                  ? AlarmDetailsPage(
                      key: ValueKey<String>('pane-alarm-$effectiveSelectedId'),
                      id: effectiveSelectedId,
                      embedded: true,
                    )
                  : const TbEmptyState(
                      icon: TbIconKind.navAlarms,
                      title: 'Select an alarm',
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
          filterStrip,
          Expanded(child: listContent),
        ],
      ),
    );
  }
}

class _AlarmRowCard extends StatelessWidget {
  const _AlarmRowCard({
    required this.alarm,
    required this.selected,
    required this.enableHero,
    required this.onTap,
    this.onAck,
    this.onClear,
  });

  final TbAlarmInfo alarm;
  final bool selected;
  final bool enableHero;
  final VoidCallback onTap;
  final VoidCallback? onAck;
  final VoidCallback? onClear;

  Color _accentFor(TbStatusColors colors, AlarmSeverity severity) {
    return switch (severity) {
      AlarmSeverity.critical => colors.critical,
      AlarmSeverity.major => colors.major,
      AlarmSeverity.minor => colors.minor,
      AlarmSeverity.warning => colors.warning,
      AlarmSeverity.indeterminate => colors.indeterminate,
    };
  }

  String _relativeTime(int epochMs) {
    if (epochMs <= 0) return 'now';
    final diff = DateTime.now().difference(
      DateTime.fromMillisecondsSinceEpoch(epochMs),
    );
    if (diff.inSeconds < 60) return 'now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return 'U';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final statusColors = TbStatusColors.of(context);
    final accent = alarm.cleared
        ? statusColors.cleared
        : _accentFor(statusColors, alarm.severity);

    final iconWidget = TbIcon(
      TbIcons.kindForSeverity(alarm.severity),
      size: DesignTokens.iconMedium,
      color: accent,
      semanticLabel: '${alarm.severity.label} alarm',
    );

    final heroOrIcon = enableHero
        ? Hero(tag: 'alarm-${alarm.id}', child: iconWidget)
        : iconWidget;

    return Material(
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
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border(left: BorderSide(color: accent, width: 4)),
          ),
          child: Padding(
            padding: DesignTokens.cardPadding,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: DesignTokens.spacing8,
              children: [
                // Line 1: Severity icon + Alarm type + 1-word badge
                LayoutBuilder(
                  builder: (context, constraints) => Row(
                    children: [
                      heroOrIcon,
                      const SizedBox(width: DesignTokens.spacing8),
                      Expanded(
                        child: Text(
                          alarm.type,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: scheme.onSurface,
                          ),
                        ),
                      ),
                      const SizedBox(width: DesignTokens.spacing8),
                      // Non-flex children are laid out against the full row
                      // width, so cap the badge at what the icon and gaps leave.
                      ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth:
                              (constraints.maxWidth -
                                      DesignTokens.iconMedium -
                                      DesignTokens.spacing8 * 2)
                                  .clamp(0.0, double.infinity),
                        ),
                        child: alarm.cleared
                            ? TbStatusBadge.cleared(compact: true)
                            : TbStatusBadge.severity(
                                alarm.severity,
                                compact: true,
                              ),
                      ),
                    ],
                  ),
                ),
                // Line 2: Originator + relative time + assignee avatar
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${alarm.displayOriginator} · ${alarm.acknowledged ? 'ACK' : 'UNACK'}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    const SizedBox(width: DesignTokens.spacing8),
                    Text(
                      _relativeTime(alarm.createdTime),
                      style: TbTextStyles.tabular(
                        textTheme.labelSmall ?? TbTextStyles.labelSmall,
                      ).copyWith(color: scheme.onSurfaceVariant),
                    ),
                    if (alarm.assigneeName != null &&
                        alarm.assigneeName!.isNotEmpty) ...[
                      const SizedBox(width: DesignTokens.spacing8),
                      UserInfoAvatarWidget(
                        shortName: _initials(alarm.assigneeName!),
                        size: DesignTokens.iconMedium,
                        semanticLabel: 'Assigned to ${alarm.assigneeName}',
                      ),
                    ],
                  ],
                ),
                // Line 3: Quick Ack / Clear actions (>=48dp touch targets)
                if (onAck != null || onClear != null)
                  Wrap(
                    spacing: DesignTokens.spacing8,
                    runSpacing: DesignTokens.spacing4,
                    children: [
                      if (onAck != null)
                        TextButton.icon(
                          key: Key('quick-ack-${alarm.id}'),
                          style: TextButton.styleFrom(
                            minimumSize: const Size(
                              DesignTokens.minTouchTarget,
                              DesignTokens.minTouchTarget,
                            ),
                          ),
                          onPressed: onAck,
                          icon: const Icon(
                            Icons.check,
                            size: DesignTokens.iconSmall,
                          ),
                          label: const Text('Ack'),
                        ),
                      if (onClear != null)
                        TextButton.icon(
                          key: Key('quick-clear-${alarm.id}'),
                          style: TextButton.styleFrom(
                            minimumSize: const Size(
                              DesignTokens.minTouchTarget,
                              DesignTokens.minTouchTarget,
                            ),
                          ),
                          onPressed: onClear,
                          icon: const Icon(
                            Icons.done_all,
                            size: DesignTokens.iconSmall,
                          ),
                          label: const Text('Clear'),
                        ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
