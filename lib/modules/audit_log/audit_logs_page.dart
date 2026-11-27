import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:thingsboard_democloud_app/config/themes/design_tokens.dart';
import 'package:thingsboard_democloud_app/core/api/controllers/audit_log_controller.dart';
import 'package:thingsboard_democloud_app/core/models/audit_log_models.dart';
import 'package:thingsboard_democloud_app/core/models/entity_id.dart';
import 'package:thingsboard_democloud_app/core/models/tb_failure.dart';
import 'package:thingsboard_democloud_app/widgets/icons/tb_icons.dart';
import 'package:thingsboard_democloud_app/widgets/tb_app_bar.dart';
import 'package:thingsboard_democloud_app/widgets/tb_app_search_bar.dart';
import 'package:thingsboard_democloud_app/widgets/tb_empty_state.dart';
import 'package:thingsboard_democloud_app/widgets/tb_list_row.dart';
import 'package:thingsboard_democloud_app/widgets/tb_section_card.dart';
import 'package:thingsboard_democloud_app/widgets/tb_motion.dart';
import 'package:thingsboard_democloud_app/widgets/tb_shimmer.dart';
import 'package:thingsboard_democloud_app/widgets/tb_status_badge.dart';

const List<String> _kActionTypes = [
  'LOGIN',
  'LOGOUT',
  'ADDED',
  'UPDATED',
  'DELETED',
  'RPC_CALL',
  'ALARM_ACK',
  'ALARM_CLEAR',
];

/// Audit logs activity timeline with action-type filter chips, search,
/// formatted JSON bottom sheet inspection, and RBAC 403 handling.
class AuditLogsPage extends ConsumerStatefulWidget {
  const AuditLogsPage({super.key});

  @override
  ConsumerState<AuditLogsPage> createState() => _AuditLogsPageState();
}

class _AuditLogsPageState extends ConsumerState<AuditLogsPage> {
  final ScrollController _scrollController = ScrollController();
  String? _selectedAction;
  String? _searchQuery;
  bool _isSearching = false;

  TbAuditLogQuery get _query => TbAuditLogQuery(
    textSearch: _searchQuery,
    actionTypes: _selectedAction != null ? [_selectedAction!] : const [],
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
      ref.read(auditLogsListProvider(_query).notifier).loadNextPage();
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

  void _openDetailsSheet(BuildContext context, TbAuditLog log) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final jsonStr = log.actionData.isNotEmpty
        ? const JsonEncoder.withIndent('  ').convert(log.actionData)
        : 'No extra payload recorded';

    showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (bottomSheetContext) {
        return DraggableScrollableSheet(
          initialChildSize: 0.6,
          minChildSize: 0.4,
          maxChildSize: 0.9,
          expand: false,
          builder: (context, scrollController) {
            return Container(
              decoration: BoxDecoration(
                color: scheme.surface,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(DesignTokens.radiusXl),
                ),
              ),
              child: Column(
                children: [
                  Center(
                    child: Container(
                      margin: const EdgeInsets.only(top: DesignTokens.spacing8),
                      width: 32,
                      height: 4,
                      decoration: BoxDecoration(
                        color: scheme.onSurfaceVariant.withValues(alpha: 0.4),
                        borderRadius: DesignTokens.borderRadiusRound,
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      DesignTokens.spacing16,
                      DesignTokens.spacing12,
                      DesignTokens.spacing16,
                      DesignTokens.spacing8,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Audit Log Details',
                            style: textTheme.titleMedium?.copyWith(
                              color: scheme.onSurface,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Close',
                          constraints: const BoxConstraints(
                            minWidth: DesignTokens.minTouchTarget,
                            minHeight: DesignTokens.minTouchTarget,
                          ),
                          padding: DesignTokens.paddingZero,
                          icon: const Icon(Icons.close),
                          onPressed: () =>
                              Navigator.of(bottomSheetContext).pop(),
                        ),
                      ],
                    ),
                  ),
                  Divider(
                    height: 1,
                    thickness: 1,
                    color: scheme.outlineVariant,
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      controller: scrollController,
                      padding: DesignTokens.paddingMedium,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          TbSectionCard(
                            title: 'Details',
                            trailing: _statusBadge(log.isSuccess),
                            child: Column(
                              children: [
                                TbKvRow(
                                  label: 'Entity',
                                  value:
                                      '${log.entityName} (${log.entityType.wireValue})',
                                ),
                                TbKvRow(label: 'Action', value: log.actionType),
                                TbKvRow(
                                  label: 'User',
                                  value: log.userName.isNotEmpty
                                      ? log.userName
                                      : (log.userId ?? 'System'),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: DesignTokens.spacing12),
                          if (log.failureDetails != null &&
                              log.failureDetails!.isNotEmpty) ...[
                            const SizedBox(height: DesignTokens.spacing8),
                            Text(
                              'Failure Details',
                              style: textTheme.labelMedium?.copyWith(
                                color: scheme.error,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: DesignTokens.spacing4),
                            Container(
                              padding: DesignTokens.cardPadding,
                              decoration: BoxDecoration(
                                color: scheme.errorContainer,
                                borderRadius: DesignTokens.borderRadiusMedium,
                              ),
                              child: Text(
                                log.failureDetails!,
                                style: textTheme.bodySmall?.copyWith(
                                  color: scheme.onErrorContainer,
                                ),
                              ),
                            ),
                            const SizedBox(height: DesignTokens.spacing12),
                          ],
                          const SizedBox(height: DesignTokens.spacing8),
                          Text(
                            'Action Payload (JSON)',
                            style: textTheme.labelMedium?.copyWith(
                              color: scheme.onSurfaceVariant,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: DesignTokens.spacing4),
                          Container(
                            padding: DesignTokens.cardPadding,
                            decoration: BoxDecoration(
                              color: scheme.surfaceContainerHigh,
                              borderRadius: DesignTokens.borderRadiusMedium,
                            ),
                            child: SelectableText(
                              jsonStr,
                              style: textTheme.bodySmall?.copyWith(
                                fontFamily: 'monospace',
                                color: scheme.onSurface,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final auditLogsAsync = ref.watch(auditLogsListProvider(_query));

    final appBar = _isSearching
        ? TbAppSearchBar(
            searchHint: 'Search audit logs...',
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
            title: const Text('Audit Logs'),
            actions: [
              IconButton(
                tooltip: 'Search audit logs',
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
        bottom: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: DesignTokens.maxReadableWidth,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(
                    horizontal: DesignTokens.spacing16,
                    vertical: DesignTokens.spacing8,
                  ),
                  child: Row(
                    spacing: DesignTokens.spacing8,
                    children: [
                      FilterChip(
                        label: const Text('All Actions'),
                        selected: _selectedAction == null,
                        onSelected: (_) =>
                            setState(() => _selectedAction = null),
                      ),
                      for (final action in _kActionTypes)
                        FilterChip(
                          label: Text(action),
                          selected: _selectedAction == action,
                          onSelected: (_) =>
                              setState(() => _selectedAction = action),
                        ),
                    ],
                  ),
                ),
                Expanded(
                  child: auditLogsAsync.when(
                    error: (error, _) {
                      final failure = error is TbFailure ? error : null;
                      final is403 =
                          failure?.type == TbFailureType.permissionDenied;
                      return TbEmptyState(
                        icon: TbIconKind.auditLog,
                        title: is403
                            ? 'Access Restricted'
                            : 'Failed to load audit logs',
                        subtitle: is403
                            ? 'You do not have permission to view audit logs.'
                            : (failure?.message ?? error.toString()),
                        actionLabel: is403 ? null : 'Retry',
                        onAction: is403
                            ? null
                            : () => ref
                                  .read(auditLogsListProvider(_query).notifier)
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
                        final isFiltered =
                            _searchQuery != null || _selectedAction != null;
                        return TbEmptyState(
                          icon: TbIconKind.auditLog,
                          title: isFiltered
                              ? 'No matching activity'
                              : 'No audit logs recorded',
                          subtitle: isFiltered
                              ? 'Try clearing the search or action filter.'
                              : 'System and user events will appear here.',
                          actionLabel: isFiltered ? 'Clear filters' : null,
                          onAction: isFiltered
                              ? () => setState(() {
                                  _searchQuery = null;
                                  _selectedAction = null;
                                  _isSearching = false;
                                })
                              : null,
                        );
                      }

                      return RefreshIndicator(
                        onRefresh: () => ref
                            .read(auditLogsListProvider(_query).notifier)
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

                            final log = pagedState.items[index];
                            return TbStaggeredEntry(
                              index: index,
                              child: _AuditLogRow(
                                log: log,
                                onTap: () => _openDetailsSheet(context, log),
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

TbStatusBadge _statusBadge(bool success, {Key? key}) => TbStatusBadge(
  key: key,
  label: success ? 'SUCCESS' : 'FAILED',
  icon: success ? TbIconKind.statusCleared : TbIconKind.severityCritical,
  tone: success ? TbStatusTone.cleared : TbStatusTone.critical,
  compact: true,
);

class _AuditLogRow extends StatelessWidget {
  const _AuditLogRow({required this.log, required this.onTap});

  final TbAuditLog log;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    final formattedTime = log.createdTime > 0
        ? DateFormat.MMMd().add_jm().format(
            DateTime.fromMillisecondsSinceEpoch(log.createdTime),
          )
        : '';
    final meta = [
      log.actionType,
      formattedTime,
      log.userName,
    ].where((e) => e.isNotEmpty).join(' · ');

    final iconKind = switch (log.entityType) {
      EntityType.device => TbIconKind.sensorNode,
      EntityType.asset => TbIconKind.assetBuilding,
      EntityType.customer => TbIconKind.customerOrg,
      EntityType.dashboard => TbIconKind.dashboardTile,
      EntityType.alarm => TbIconKind.severityCritical,
      _ => TbIconKind.auditLog,
    };

    return Semantics(
      button: true,
      label: 'Audit log ${log.actionType} on ${log.entityName}',
      child: TbListRow(
        title: log.entityName.isNotEmpty ? log.entityName : log.actionType,
        meta: meta,
        leading: TbIcon(
          iconKind,
          size: DesignTokens.iconSmall,
          color: scheme.primary,
        ),
        trailing: _statusBadge(
          log.isSuccess,
          key: ValueKey('audit-status-${log.id}'),
        ),
        onTap: onTap,
      ),
    );
  }
}
