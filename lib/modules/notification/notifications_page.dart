import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:thingsboard_democloud_app/config/themes/design_tokens.dart';
import 'package:thingsboard_democloud_app/config/themes/tb_status_colors.dart';
import 'package:thingsboard_democloud_app/core/api/controllers/notification_controller.dart';
import 'package:thingsboard_democloud_app/core/models/alarm_models.dart';
import 'package:thingsboard_democloud_app/core/models/notification_models.dart';
import 'package:thingsboard_democloud_app/core/models/tb_failure.dart';
import 'package:thingsboard_democloud_app/widgets/icons/tb_icons.dart';
import 'package:thingsboard_democloud_app/widgets/tb_app_bar.dart';
import 'package:thingsboard_democloud_app/widgets/tb_empty_state.dart';
import 'package:thingsboard_democloud_app/widgets/tb_list_row.dart';
import 'package:thingsboard_democloud_app/widgets/tb_motion.dart';
import 'package:thingsboard_democloud_app/widgets/tb_shimmer.dart';
import 'package:thingsboard_democloud_app/widgets/tb_status_badge.dart';

/// Notifications inbox screen with All/Unread filter, mark-all-read action,
/// multi-select delete/mark-read, Dismissible swipe delete, and live WS sync.
class NotificationsPage extends ConsumerStatefulWidget {
  const NotificationsPage({super.key});

  @override
  ConsumerState<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends ConsumerState<NotificationsPage> {
  final ScrollController _scrollController = ScrollController();
  bool _unreadOnly = false;
  final Set<String> _selectedIds = <String>{};

  bool get _isSelectionMode => _selectedIds.isNotEmpty;

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
      ref.read(notificationsListProvider(_unreadOnly).notifier).loadNextPage();
    }
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _toggleSelection(String id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
      } else {
        _selectedIds.add(id);
      }
    });
  }

  void _clearSelection() {
    setState(() {
      _selectedIds.clear();
    });
  }

  Future<void> _markSelectedAsRead() async {
    final notifier = ref.read(notificationsListProvider(_unreadOnly).notifier);
    final ids = _selectedIds.toList();
    _clearSelection();
    for (final id in ids) {
      await notifier.markAsRead(id);
    }
  }

  Future<void> _deleteSelected() async {
    final notifier = ref.read(notificationsListProvider(_unreadOnly).notifier);
    final ids = _selectedIds.toList();
    _clearSelection();
    for (final id in ids) {
      await notifier.deleteNotification(id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final notificationsAsync = ref.watch(
      notificationsListProvider(_unreadOnly),
    );

    final PreferredSizeWidget appBar = _isSelectionMode
        ? AppBar(
            leading: IconButton(
              tooltip: 'Cancel selection',
              constraints: const BoxConstraints(
                minWidth: DesignTokens.minTouchTarget,
                minHeight: DesignTokens.minTouchTarget,
              ),
              icon: const Icon(Icons.close),
              onPressed: _clearSelection,
            ),
            title: Text('${_selectedIds.length} selected'),
            actions: [
              IconButton(
                tooltip: 'Mark selected as read',
                constraints: const BoxConstraints(
                  minWidth: DesignTokens.minTouchTarget,
                  minHeight: DesignTokens.minTouchTarget,
                ),
                icon: const Icon(Icons.mark_email_read_outlined),
                onPressed: _markSelectedAsRead,
              ),
              IconButton(
                tooltip: 'Delete selected',
                constraints: const BoxConstraints(
                  minWidth: DesignTokens.minTouchTarget,
                  minHeight: DesignTokens.minTouchTarget,
                ),
                icon: const Icon(Icons.delete_outline),
                onPressed: _deleteSelected,
              ),
            ],
          )
        : TbAppBar(
            canGoBack: true,
            title: const Text('Notifications'),
            actions: [
              IconButton(
                tooltip: 'Mark all as read',
                constraints: const BoxConstraints(
                  minWidth: DesignTokens.minTouchTarget,
                  minHeight: DesignTokens.minTouchTarget,
                ),
                icon: const Icon(Icons.done_all_rounded),
                onPressed: () => ref
                    .read(notificationsListProvider(_unreadOnly).notifier)
                    .markAllAsRead(),
              ),
            ],
          );

    return Scaffold(
      appBar: appBar,
      body: SafeArea(
        bottom: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: DesignTokens.maxReadableWidth,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: DesignTokens.spacing16,
                    vertical: DesignTokens.spacing8,
                  ),
                  child: SegmentedButton<bool>(
                    showSelectedIcon: false,
                    segments: const [
                      ButtonSegment<bool>(
                        value: false,
                        label: Text('All'),
                        icon: Icon(Icons.inbox_outlined),
                      ),
                      ButtonSegment<bool>(
                        value: true,
                        label: Text('Unread'),
                        icon: Icon(Icons.mark_email_unread_outlined),
                      ),
                    ],
                    selected: {_unreadOnly},
                    onSelectionChanged: (selected) {
                      setState(() {
                        _unreadOnly = selected.first;
                        _clearSelection();
                      });
                    },
                  ),
                ),
                Expanded(
                  child: notificationsAsync.when(
                    error: (error, _) {
                      final failure = error is TbFailure ? error : null;
                      return TbEmptyState(
                        icon: TbIconKind.notificationInbox,
                        title: 'Failed to load notifications',
                        subtitle: failure?.message ?? error.toString(),
                        actionLabel: 'Retry',
                        onAction: () => ref
                            .read(
                              notificationsListProvider(_unreadOnly).notifier,
                            )
                            .refresh(),
                        isError: true,
                      );
                    },
                    loading: () => SingleChildScrollView(
                      padding: EdgeInsets.fromLTRB(
                        DesignTokens.spacing16,
                        DesignTokens.spacing4,
                        DesignTokens.spacing16,
                        DesignTokens.bottomScrollPadding(context),
                      ),
                      child: const TbShimmerList(itemCount: 6),
                    ),
                    data: (pagedState) {
                      if (pagedState.items.isEmpty) {
                        return TbEmptyState(
                          icon: TbIconKind.notificationInbox,
                          title: _unreadOnly
                              ? 'No unread notifications'
                              : 'Inbox is empty',
                          subtitle: _unreadOnly
                              ? 'All caught up! Check back later.'
                              : 'System alerts and messages will arrive here.',
                        );
                      }

                      return RefreshIndicator(
                        onRefresh: () => ref
                            .read(
                              notificationsListProvider(_unreadOnly).notifier,
                            )
                            .refresh(),
                        child: ListView.separated(
                          controller: _scrollController,
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: EdgeInsets.only(
                            bottom: DesignTokens.bottomScrollPadding(context),
                          ),
                          itemCount:
                              pagedState.items.length +
                              (pagedState.isLoadingMore ? 1 : 0),
                          separatorBuilder: (_, _) => const Divider(
                            height: 1,
                            indent: DesignTokens.spacing16,
                          ),
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

                            final notification = pagedState.items[index];
                            final isSelected = _selectedIds.contains(
                              notification.id,
                            );

                            return TbStaggeredEntry(
                              index: index,
                              child: Dismissible(
                                key: ValueKey(notification.id),
                                direction: DismissDirection.endToStart,
                                background: Container(
                                  alignment: Alignment.centerRight,
                                  padding: const EdgeInsets.only(
                                    right: DesignTokens.spacing20,
                                  ),
                                  color: scheme.error,
                                  child: Icon(
                                    Icons.delete_outline,
                                    color: scheme.onError,
                                  ),
                                ),
                                onDismissed: (_) {
                                  ref
                                      .read(
                                        notificationsListProvider(
                                          _unreadOnly,
                                        ).notifier,
                                      )
                                      .deleteNotification(notification.id);
                                },
                                child: _NotificationCard(
                                  notification: notification,
                                  isSelected: isSelected,
                                  isSelectionMode: _isSelectionMode,
                                  onTap: () {
                                    if (_isSelectionMode) {
                                      _toggleSelection(notification.id);
                                    } else if (!notification.isRead) {
                                      ref
                                          .read(
                                            notificationsListProvider(
                                              _unreadOnly,
                                            ).notifier,
                                          )
                                          .markAsRead(notification.id);
                                    }
                                  },
                                  onLongPress: () =>
                                      _toggleSelection(notification.id),
                                ),
                              ),
                            );
                          },
                        ),
                      );
                    },
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

class _NotificationCard extends StatelessWidget {
  const _NotificationCard({
    required this.notification,
    required this.isSelected,
    required this.isSelectionMode,
    required this.onTap,
    required this.onLongPress,
  });

  final TbNotification notification;
  final bool isSelected;
  final bool isSelectionMode;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final statusColors = TbStatusColors.of(context);

    final formattedTime = notification.createdTime > 0
        ? DateFormat.MMMd().add_jm().format(
            DateTime.fromMillisecondsSinceEpoch(notification.createdTime),
          )
        : '';
    final meta = [
      formattedTime,
      notification.deliveryMethod,
    ].where((e) => e.isNotEmpty).join(' · ');

    final (accentColor, iconKind) = notification.severity != null
        ? switch (notification.severity!) {
            AlarmSeverity.critical => (
              statusColors.critical,
              TbIconKind.severityCritical,
            ),
            AlarmSeverity.major => (
              statusColors.major,
              TbIconKind.severityMajor,
            ),
            AlarmSeverity.minor => (
              statusColors.minor,
              TbIconKind.severityMinor,
            ),
            AlarmSeverity.warning => (
              statusColors.warning,
              TbIconKind.severityWarning,
            ),
            AlarmSeverity.indeterminate => (
              statusColors.indeterminate,
              TbIconKind.severityIndeterminate,
            ),
          }
        : (scheme.primary, TbIconKind.notificationInbox);

    return Semantics(
      button: true,
      label:
          'Notification ${notification.subject}${notification.isRead ? "" : ", unread"}',
      child: Material(
        color: isSelected
            ? scheme.primaryContainer.withValues(alpha: 0.3)
            : scheme.surface,
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          child: TbListRow(
            title: notification.subject,
            meta: meta,
            leading: isSelectionMode
                ? Checkbox(value: isSelected, onChanged: (_) => onTap())
                : Container(
                    width: DesignTokens.minTouchTarget - 10,
                    height: DesignTokens.minTouchTarget - 10,
                    decoration: BoxDecoration(
                      color: accentColor.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: TbIcon(
                        iconKind,
                        size: DesignTokens.iconSmall,
                        color: accentColor,
                      ),
                    ),
                  ),
            trailing: notification.isRead
                ? null
                : TbStatusBadge(
                    key: ValueKey('notification-unread-${notification.id}'),
                    label: 'NEW',
                    icon: TbIconKind.notificationInbox,
                    tone: TbStatusTone.indeterminate,
                    compact: true,
                  ),
          ),
        ),
      ),
    );
  }
}
