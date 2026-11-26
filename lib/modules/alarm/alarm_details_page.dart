import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:thingsboard_democloud_app/config/routes/router.dart';
import 'package:thingsboard_democloud_app/config/themes/design_tokens.dart';
import 'package:thingsboard_democloud_app/config/themes/tb_status_colors.dart';
import 'package:thingsboard_democloud_app/config/themes/tb_text_styles.dart';
import 'package:thingsboard_democloud_app/core/api/controllers/alarm_controller.dart';
import 'package:thingsboard_democloud_app/core/models/alarm_models.dart';
import 'package:thingsboard_democloud_app/core/models/tb_failure.dart';
import 'package:thingsboard_democloud_app/modules/alarm/widgets/user_info_avatar_widget.dart';
import 'package:thingsboard_democloud_app/widgets/icons/tb_icons.dart';
import 'package:thingsboard_democloud_app/widgets/tb_app_bar.dart';
import 'package:thingsboard_democloud_app/widgets/tb_empty_state.dart';
import 'package:thingsboard_democloud_app/widgets/tb_list_row.dart';
import 'package:thingsboard_democloud_app/widgets/tb_section_card.dart';
import 'package:thingsboard_democloud_app/widgets/tb_shimmer.dart';
import 'package:thingsboard_democloud_app/widgets/tb_status_badge.dart';

/// Material 3 alarm detail screen with Hero transition, dynamic assignee picker,
/// Ack/Clear confirmations, activity refresh, and live comments composer.
class AlarmDetailsPage extends ConsumerStatefulWidget {
  const AlarmDetailsPage({super.key, required this.id, this.embedded = false});

  final String id;
  final bool embedded;

  @override
  ConsumerState<AlarmDetailsPage> createState() => _AlarmDetailsPageState();
}

class _AlarmDetailsPageState extends ConsumerState<AlarmDetailsPage> {
  final TextEditingController _commentController = TextEditingController();
  static final DateFormat _dateTimeFormat = DateFormat('yyyy-MM-dd HH:mm');
  bool _mutating = false;
  bool _postingComment = false;

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _refreshAll() async {
    ref.invalidate(alarmDetailsProvider(widget.id));
    ref.invalidate(alarmCommentsProvider(widget.id));
  }

  Future<void> _confirmAndRun({
    required String title,
    required String actionLabel,
    required Future<void> Function() action,
    required String successText,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: Text(title),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: Key('confirm-${actionLabel.toLowerCase()}-button'),
            onPressed: () => Navigator.of(dialogCtx).pop(true),
            child: Text(actionLabel),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _mutating = true);
    try {
      await action();
      ref.invalidate(alarmsListProvider(null));
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(successText)));
    } catch (e) {
      if (!mounted) return;
      final msg = e is TbFailure ? e.message : e.toString();
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(msg)));
    } finally {
      if (mounted) setState(() => _mutating = false);
    }
  }

  Future<void> _openAssigneePicker(TbAlarmInfo alarm) async {
    final picked =
        await showModalBottomSheet<({bool unassign, TbUserEmailInfo? user})>(
          context: context,
          useRootNavigator: true,
          isScrollControlled: true,
          builder: (sheetCtx) => _AssigneePickerSheet(
            alarmId: alarm.id,
            currentAssigneeId: alarm.assigneeId,
          ),
        );
    if (picked == null || !mounted) return;

    setState(() => _mutating = true);
    try {
      await ref
          .read(alarmDetailsProvider(widget.id).notifier)
          .assign(picked.unassign ? null : picked.user);
      ref.invalidate(alarmsListProvider(null));
      if (!mounted) return;
      final label = picked.unassign
          ? 'Alarm unassigned'
          : 'Assigned to ${picked.user?.displayName ?? ''}';
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(label)));
    } catch (e) {
      if (!mounted) return;
      final msg = e is TbFailure ? e.message : e.toString();
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(msg)));
    } finally {
      if (mounted) setState(() => _mutating = false);
    }
  }

  Future<void> _submitComment() async {
    final text = _commentController.text.trim();
    if (text.isEmpty || _postingComment) return;
    setState(() => _postingComment = true);
    try {
      await ref
          .read(alarmCommentsProvider(widget.id).notifier)
          .addComment(text);
      _commentController.clear();
    } catch (e) {
      if (!mounted) return;
      final msg = e is TbFailure ? e.message : e.toString();
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(msg)));
    } finally {
      if (mounted) setState(() => _postingComment = false);
    }
  }

  String _formatTs(int epochMs) {
    if (epochMs <= 0) return '—';
    return _dateTimeFormat.format(DateTime.fromMillisecondsSinceEpoch(epochMs));
  }

  String _initialsFromName(String? name) {
    if (name == null || name.trim().isEmpty) return 'U';
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }

  Color _severityAccent(TbStatusColors colors, AlarmSeverity severity) {
    return switch (severity) {
      AlarmSeverity.critical => colors.critical,
      AlarmSeverity.major => colors.major,
      AlarmSeverity.minor => colors.minor,
      AlarmSeverity.warning => colors.warning,
      AlarmSeverity.indeterminate => colors.indeterminate,
    };
  }

  Color _severityContainer(TbStatusColors colors, AlarmSeverity severity) {
    return switch (severity) {
      AlarmSeverity.critical => colors.criticalContainer,
      AlarmSeverity.major => colors.majorContainer,
      AlarmSeverity.minor => colors.minorContainer,
      AlarmSeverity.warning => colors.warningContainer,
      AlarmSeverity.indeterminate => colors.indeterminateContainer,
    };
  }

  @override
  Widget build(BuildContext context) {
    final alarmAsync = ref.watch(alarmDetailsProvider(widget.id));
    final commentsAsync = ref.watch(alarmCommentsProvider(widget.id));
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final statusColors = TbStatusColors.of(context);

    final titleText = alarmAsync.valueOrNull?.type ?? 'Alarm';

    return Scaffold(
      appBar: widget.embedded
          ? null
          : TbAppBar(
              title: Text(titleText),
              showLoadingIndicator: _mutating,
              actions: [
                IconButton(
                  key: const Key('alarm-details-refresh-button'),
                  tooltip: 'Refresh alarm',
                  constraints: const BoxConstraints(
                    minWidth: DesignTokens.minTouchTarget,
                    minHeight: DesignTokens.minTouchTarget,
                  ),
                  icon: const Icon(Icons.refresh),
                  onPressed: _refreshAll,
                ),
              ],
            ),
      body: alarmAsync.when(
        loading: () => const SingleChildScrollView(
          padding: DesignTokens.paddingMedium,
          child: TbShimmerList(itemCount: 3),
        ),
        error: (err, _) => TbEmptyState(
          icon: TbIconKind.severityCritical,
          title: 'Failed to load alarm',
          subtitle: err is TbFailure ? err.message : err.toString(),
          isError: true,
          actionLabel: 'Retry',
          onAction: _refreshAll,
        ),
        data: (alarm) {
          final accent = _severityAccent(statusColors, alarm.severity);
          final containerBg = _severityContainer(statusColors, alarm.severity);
          final severityIconBox = Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: containerBg,
              borderRadius: DesignTokens.borderRadiusMedium,
            ),
            alignment: Alignment.center,
            child: TbIcon(
              TbIcons.kindForSeverity(alarm.severity),
              size: DesignTokens.iconMedium,
              color: accent,
              semanticLabel: '${alarm.severity.label} severity',
            ),
          );

          final hasActions =
              !alarm.acknowledged ||
              !alarm.cleared ||
              (alarm.dashboardId != null && alarm.dashboardId!.isNotEmpty);
          final heroIcon = widget.embedded
              ? severityIconBox
              : Hero(tag: 'alarm-${alarm.id}', child: severityIconBox);

          return Column(
            children: [
              Expanded(
                child: RefreshIndicator(
                  onRefresh: _refreshAll,
                  child: CustomScrollView(
                    slivers: [
                      SliverPadding(
                        padding: DesignTokens.paddingMedium,
                        sliver: SliverToBoxAdapter(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            spacing: DesignTokens.spacing12,
                            children: [
                              // Concise header pill card
                              Container(
                                padding: DesignTokens.cardPadding,
                                decoration: BoxDecoration(
                                  color: scheme.surfaceContainerLow,
                                  borderRadius: DesignTokens.borderRadiusLarge,
                                  border: Border.all(
                                    color: scheme.outlineVariant,
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  spacing: DesignTokens.spacing12,
                                  children: [
                                    Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        heroIcon,
                                        const SizedBox(
                                          width: DesignTokens.spacing12,
                                        ),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            spacing: DesignTokens.spacing4,
                                            children: [
                                              Text(
                                                alarm.type,
                                                style: textTheme.titleMedium
                                                    ?.copyWith(
                                                      fontWeight:
                                                          FontWeight.w600,
                                                    ),
                                              ),
                                              Text(
                                                alarm.displayOriginator,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: textTheme.bodyMedium
                                                    ?.copyWith(
                                                      color: scheme
                                                          .onSurfaceVariant,
                                                    ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        if (widget.embedded)
                                          IconButton(
                                            key: const Key(
                                              'alarm-embedded-refresh-button',
                                            ),
                                            tooltip: 'Refresh alarm',
                                            constraints: const BoxConstraints(
                                              minWidth:
                                                  DesignTokens.minTouchTarget,
                                              minHeight:
                                                  DesignTokens.minTouchTarget,
                                            ),
                                            icon: const Icon(Icons.refresh),
                                            onPressed: _refreshAll,
                                          ),
                                      ],
                                    ),
                                    Wrap(
                                      spacing: DesignTokens.spacing8,
                                      runSpacing: DesignTokens.spacing8,
                                      children: [
                                        TbStatusBadge.severity(alarm.severity),
                                        if (alarm.cleared)
                                          TbStatusBadge.cleared()
                                        else
                                          TbStatusBadge(
                                            label: alarm.acknowledged
                                                ? 'ACK'
                                                : 'UNACK',
                                            icon: alarm.acknowledged
                                                ? TbIconKind.statusCleared
                                                : TbIconKind.navAlarms,
                                            tone: alarm.acknowledged
                                                ? TbStatusTone.online
                                                : TbStatusTone.warning,
                                          ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),

                              if (hasActions)
                                TbSectionCard(
                                  title: 'Actions',
                                  child: Wrap(
                                    spacing: DesignTokens.spacing8,
                                    runSpacing: DesignTokens.spacing8,
                                    children: [
                                      if (!alarm.acknowledged)
                                        FilledButton.tonalIcon(
                                          key: const Key('alarm-ack-button'),
                                          onPressed: _mutating
                                              ? null
                                              : () => _confirmAndRun(
                                                  title: 'Acknowledge alarm?',
                                                  actionLabel: 'Acknowledge',
                                                  action: () => ref
                                                      .read(
                                                        alarmDetailsProvider(
                                                          widget.id,
                                                        ).notifier,
                                                      )
                                                      .acknowledge(),
                                                  successText:
                                                      'Alarm acknowledged',
                                                ),
                                          icon: const Icon(
                                            Icons.check,
                                            size: DesignTokens.iconSmall,
                                          ),
                                          label: const Text('Acknowledge'),
                                        ),
                                      if (!alarm.cleared)
                                        FilledButton.icon(
                                          key: const Key('alarm-clear-button'),
                                          onPressed: _mutating
                                              ? null
                                              : () => _confirmAndRun(
                                                  title: 'Clear alarm?',
                                                  actionLabel: 'Clear',
                                                  action: () => ref
                                                      .read(
                                                        alarmDetailsProvider(
                                                          widget.id,
                                                        ).notifier,
                                                      )
                                                      .clear(),
                                                  successText: 'Alarm cleared',
                                                ),
                                          icon: const Icon(
                                            Icons.done_all,
                                            size: DesignTokens.iconSmall,
                                          ),
                                          label: const Text('Clear'),
                                        ),
                                      if (alarm.dashboardId != null &&
                                          alarm.dashboardId!.isNotEmpty)
                                        OutlinedButton.icon(
                                          onPressed: () {
                                            final router = GoRouter.maybeOf(
                                              context,
                                            );
                                            router?.push(
                                              AppRoutes.dashboardDetailsPath(
                                                alarm.dashboardId!,
                                              ),
                                            );
                                          },
                                          icon: TbIcon(
                                            TbIconKind.dashboardTile,
                                            size: DesignTokens.iconSmall,
                                            color: scheme.primary,
                                          ),
                                          label: const Text('Dashboard'),
                                        ),
                                    ],
                                  ),
                                ),
                              TbSectionCard(
                                title: 'Assignee',
                                child: TbListRow(
                                  key: const Key('alarm-assignee-tile'),
                                  leading: UserInfoAvatarWidget(
                                    shortName: _initialsFromName(
                                      alarm.assigneeName,
                                    ),
                                    semanticLabel: alarm.assigneeName != null
                                        ? 'Assigned to ${alarm.assigneeName}'
                                        : 'Unassigned',
                                  ),
                                  title: alarm.assigneeName ?? 'Unassigned',
                                  meta: alarm.assigneeEmail ?? 'Tap to assign',
                                  trailing: const Icon(Icons.chevron_right),
                                  onTap: _mutating
                                      ? null
                                      : () => _openAssigneePicker(alarm),
                                ),
                              ),
                              TbSectionCard(
                                title: 'Timeline & details',
                                child: Column(
                                  children: [
                                    TbKvRow(
                                      label: 'Created',
                                      value: _formatTs(alarm.createdTime),
                                    ),
                                    if (alarm.ackTs > 0)
                                      TbKvRow(
                                        label: 'Acknowledged',
                                        value: _formatTs(alarm.ackTs),
                                      ),
                                    if (alarm.clearTs > 0)
                                      TbKvRow(
                                        label: 'Cleared',
                                        value: _formatTs(alarm.clearTs),
                                      ),
                                    if (alarm.originator != null)
                                      TbKvRow(
                                        label: 'Originator',
                                        value: alarm
                                            .originator!
                                            .entityType
                                            .wireValue,
                                      ),
                                    for (final entry in alarm.details.entries)
                                      TbKvRow(
                                        label: entry.key,
                                        value: '${entry.value}',
                                      ),
                                  ],
                                ),
                              ),
                              TbSectionCard(
                                title: 'Activity',
                                trailing: IconButton(
                                  key: const Key(
                                    'alarm-activity-refresh-button',
                                  ),
                                  tooltip: 'Refresh activity',
                                  constraints: const BoxConstraints(
                                    minWidth: DesignTokens.minTouchTarget,
                                    minHeight: DesignTokens.minTouchTarget,
                                  ),
                                  icon: const Icon(Icons.refresh),
                                  onPressed: () => ref.invalidate(
                                    alarmCommentsProvider(widget.id),
                                  ),
                                ),
                                child: commentsAsync.when(
                                  loading: () =>
                                      const TbShimmerList(itemCount: 2),
                                  error: (err, _) => TbEmptyState(
                                    icon: TbIconKind.severityCritical,
                                    title: 'Activity unavailable',
                                    subtitle: err is TbFailure
                                        ? err.message
                                        : err.toString(),
                                    isError: true,
                                    actionLabel: 'Retry',
                                    onAction: () => ref.invalidate(
                                      alarmCommentsProvider(widget.id),
                                    ),
                                  ),
                                  data: (commentsState) {
                                    if (commentsState.items.isEmpty) {
                                      return const TbEmptyState(
                                        icon: TbIconKind.auditLog,
                                        title: 'No activity yet',
                                      );
                                    }
                                    return Column(
                                      spacing: DesignTokens.spacing8,
                                      children: [
                                        for (final comment
                                            in commentsState.items)
                                          _AlarmCommentTile(
                                            comment: comment,
                                            formattedTime: _formatTs(
                                              comment.createdTime,
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
                      ),
                    ],
                  ),
                ),
              ),
              // Pinned comment composer
              SafeArea(
                top: false,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(
                    DesignTokens.spacing16,
                    DesignTokens.spacing8,
                    DesignTokens.spacing8,
                    DesignTokens.spacing8,
                  ),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerLow,
                    border: Border(
                      top: BorderSide(color: scheme.outlineVariant),
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          key: const Key('alarm-comment-input'),
                          controller: _commentController,
                          textInputAction: TextInputAction.send,
                          onSubmitted: (_) => _submitComment(),
                          decoration: const InputDecoration(
                            hintText: 'Add comment...',
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: DesignTokens.spacing8),
                      IconButton(
                        key: const Key('alarm-comment-send-button'),
                        tooltip: 'Send comment',
                        constraints: const BoxConstraints(
                          minWidth: DesignTokens.minTouchTarget,
                          minHeight: DesignTokens.minTouchTarget,
                        ),
                        icon: const Icon(Icons.send),
                        onPressed: _postingComment ? null : _submitComment,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _AlarmCommentTile extends StatelessWidget {
  const _AlarmCommentTile({required this.comment, required this.formattedTime});

  final TbAlarmComment comment;
  final String formattedTime;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Container(
      padding: DesignTokens.paddingSmall,
      decoration: BoxDecoration(
        color: comment.isSystem
            ? scheme.surfaceContainerLowest
            : scheme.surfaceContainerLow,
        borderRadius: DesignTokens.borderRadiusMedium,
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (comment.isSystem)
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHigh,
                borderRadius: DesignTokens.borderRadiusRound,
              ),
              alignment: Alignment.center,
              child: TbIcon(
                TbIconKind.auditLog,
                size: DesignTokens.iconSmall,
                color: scheme.onSurfaceVariant,
              ),
            )
          else
            UserInfoAvatarWidget(shortName: comment.initials),
          const SizedBox(width: DesignTokens.spacing12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: DesignTokens.spacing2,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        comment.authorName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.labelMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: DesignTokens.spacing8),
                    Text(
                      formattedTime,
                      style: TbTextStyles.tabular(
                        textTheme.labelSmall ?? TbTextStyles.labelSmall,
                      ).copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
                Text(
                  comment.text,
                  style: textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurface,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AssigneePickerSheet extends ConsumerStatefulWidget {
  const _AssigneePickerSheet({required this.alarmId, this.currentAssigneeId});

  final String alarmId;
  final String? currentAssigneeId;

  @override
  ConsumerState<_AssigneePickerSheet> createState() =>
      _AssigneePickerSheetState();
}

class _AssigneePickerSheetState extends ConsumerState<_AssigneePickerSheet> {
  final TextEditingController _searchController = TextEditingController();
  String _search = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final assigneesAsync = ref.watch(
      alarmAssigneesProvider((alarmId: widget.alarmId, search: _search)),
    );
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        DesignTokens.spacing16,
        DesignTokens.spacing16,
        DesignTokens.spacing16,
        bottomInset + DesignTokens.spacing16,
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: DesignTokens.spacing12,
          children: [
            Text(
              'Assign alarm',
              style: textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            TextField(
              key: const Key('assignee-search-input'),
              controller: _searchController,
              onChanged: (value) => setState(() => _search = value.trim()),
              decoration: const InputDecoration(
                hintText: 'Search user',
                prefixIcon: Icon(Icons.search),
                isDense: true,
              ),
            ),
            ListTile(
              key: const Key('assignee-unassign-option'),
              minTileHeight: DesignTokens.minTouchTarget,
              leading: const Icon(Icons.person_off_outlined),
              title: const Text('Unassigned'),
              trailing: widget.currentAssigneeId == null
                  ? const Icon(Icons.check)
                  : null,
              onTap: () =>
                  Navigator.of(context).pop((unassign: true, user: null)),
            ),
            Flexible(
              child: assigneesAsync.when(
                loading: () => const SingleChildScrollView(
                  child: TbShimmerList(itemCount: 3),
                ),
                error: (err, _) => TbEmptyState(
                  icon: TbIconKind.severityCritical,
                  title: 'Failed to load users',
                  subtitle: err is TbFailure ? err.message : err.toString(),
                  isError: true,
                  actionLabel: 'Retry',
                  onAction: () => ref.invalidate(
                    alarmAssigneesProvider((
                      alarmId: widget.alarmId,
                      search: _search,
                    )),
                  ),
                ),
                data: (users) {
                  if (users.isEmpty) {
                    return const TbEmptyState(
                      icon: TbIconKind.customerOrg,
                      title: 'No matching users',
                    );
                  }
                  return ListView.builder(
                    itemCount: users.length,
                    itemBuilder: (context, index) {
                      final user = users[index];
                      final initials = user.displayName.isNotEmpty
                          ? user.displayName.substring(0, 1).toUpperCase()
                          : 'U';
                      return ListTile(
                        key: Key('assignee-option-${user.id}'),
                        minTileHeight: DesignTokens.minTouchTarget,
                        leading: UserInfoAvatarWidget(shortName: initials),
                        title: Text(
                          user.displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          user.email,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: widget.currentAssigneeId == user.id
                            ? const Icon(Icons.check)
                            : null,
                        onTap: () => Navigator.of(
                          context,
                        ).pop((unassign: false, user: user)),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
