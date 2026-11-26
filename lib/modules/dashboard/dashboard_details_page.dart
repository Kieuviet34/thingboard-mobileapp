import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:thingsboard_democloud_app/config/themes/design_tokens.dart';
import 'package:thingsboard_democloud_app/core/api/controllers/dashboard_controller.dart';
import 'package:thingsboard_democloud_app/core/api/controllers/server_config_controller.dart';
import 'package:thingsboard_democloud_app/core/api/controllers/telemetry_controller.dart';
import 'package:thingsboard_democloud_app/core/api/ws/telemetry_ws_service.dart';
import 'package:thingsboard_democloud_app/core/models/auth_models.dart';
import 'package:thingsboard_democloud_app/core/models/dashboard_models.dart';
import 'package:thingsboard_democloud_app/core/models/entity_id.dart';
import 'package:thingsboard_democloud_app/core/models/tb_failure.dart';
import 'package:thingsboard_democloud_app/core/models/telemetry_models.dart';
import 'package:thingsboard_democloud_app/widgets/icons/tb_icons.dart';
import 'package:thingsboard_democloud_app/widgets/tb_app_bar.dart';
import 'package:thingsboard_democloud_app/widgets/tb_empty_state.dart';
import 'package:thingsboard_democloud_app/widgets/tb_metric_pill.dart';
import 'package:thingsboard_democloud_app/widgets/tb_motion.dart';
import 'package:thingsboard_democloud_app/widgets/tb_shimmer.dart';
import 'package:thingsboard_democloud_app/widgets/tb_status_badge.dart';
import 'package:url_launcher/url_launcher.dart';

/// Supported time-window presets for dashboard telemetry history sparklines.
enum DashboardTimeWindow {
  h1('1h', Duration(hours: 1)),
  h24('24h', Duration(hours: 24)),
  d7('7d', Duration(days: 7));

  const DashboardTimeWindow(this.label, this.duration);

  final String label;
  final Duration duration;
}

/// Live ThingsBoard dashboard viewer with telemetry pills, sparklines,
/// time-window switching, fullscreen mode, and external browser handoff.
class DashboardDetailsPage extends ConsumerStatefulWidget {
  const DashboardDetailsPage({
    super.key,
    required this.dashboardId,
    this.embedded = false,
    this.onOpenExternal,
  });

  final String dashboardId;

  /// When `true` (e.g. right pane of tablet 2-pane layout), omits top-level
  /// back navigation and duplicate `Hero` tag.
  final bool embedded;

  /// Optional external URL launcher override for deterministic testing.
  final Future<bool> Function(Uri uri)? onOpenExternal;

  @override
  ConsumerState<DashboardDetailsPage> createState() =>
      _DashboardDetailsPageState();
}

class _DashboardDetailsPageState extends ConsumerState<DashboardDetailsPage> {
  bool _isFullscreen = false;
  DashboardTimeWindow _timeWindow = DashboardTimeWindow.h24;
  String? _lastVisitedId;
  List<String> _liveKeys = const <String>[];

  @override
  void initState() {
    super.initState();
    _recordVisit(widget.dashboardId);
  }

  @override
  void didUpdateWidget(covariant DashboardDetailsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.dashboardId != widget.dashboardId) {
      _isFullscreen = false;
      _timeWindow = DashboardTimeWindow.h24;
      _liveKeys = const <String>[];
      _recordVisit(widget.dashboardId);
    }
  }

  void _syncStableKeys(Iterable<String> nextKeys) {
    final sorted = nextKeys.toList()..sort();
    if (!listEquals(_liveKeys, sorted)) {
      _liveKeys = List<String>.unmodifiable(sorted);
    }
  }

  void _recordVisit(String id) {
    if (_lastVisitedId == id) return;
    _lastVisitedId = id;
    Future<void>.microtask(() async {
      if (!mounted) return;
      try {
        await ref
            .read(dashboardRepositoryProvider)
            .reportDashboardAction(id, 'VISIT');
        if (mounted) {
          ref.invalidate(userDashboardsInfoProvider);
        }
      } catch (_) {
        // Best-effort analytics hook; never fail detail view.
      }
    });
  }

  Future<void> _selectTimeWindow(
    DashboardTimeWindow next,
    EntityId? entityId,
  ) async {
    if (next == _timeWindow) return;
    setState(() => _timeWindow = next);
    if (entityId == null) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    final startTs = now - next.duration.inMilliseconds;
    await ref
        .read(entityTelemetryHistoryProvider(entityId).notifier)
        .loadRange(
          TbTsHistoryQuery(
            entityId: entityId,
            keys: _liveKeys,
            startTs: startTs,
            endTs: now,
          ),
        );
  }

  Future<void> _openInBrowser() async {
    final baseUrl = ref.read(serverConfigProvider).baseUrl;
    final uri = Uri.parse(baseUrl).resolve('dashboards/${widget.dashboardId}');
    final launched = widget.onOpenExternal != null
        ? await widget.onOpenExternal!(uri)
        : await launchUrl(uri, mode: LaunchMode.externalApplication);

    if (!launched && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Unable to open browser')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final dashboardAsync = ref.watch(
      dashboardDetailsProvider(widget.dashboardId),
    );
    final mode = ref.watch(serverConfigProvider.select((s) => s.mode));
    final wsState = ref.watch(wsConnectionStateProvider).valueOrNull;
    final isDemo = mode == SessionMode.demo;
    final isLiveActive = isDemo || wsState == WsConnectionState.authenticated;
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final titleText = dashboardAsync.valueOrNull?.info.title ?? 'Dashboard';

    final titleBadge = Container(
      padding: DesignTokens.paddingXs,
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: DesignTokens.borderRadiusSmall,
      ),
      child: TbIcon(
        TbIconKind.dashboardTile,
        size: DesignTokens.iconSmall,
        color: scheme.onPrimaryContainer,
      ),
    );

    final actionButtons = <Widget>[
      IconButton(
        tooltip: 'Open in browser',
        constraints: const BoxConstraints(
          minWidth: DesignTokens.minTouchTarget,
          minHeight: DesignTokens.minTouchTarget,
        ),
        icon: const Icon(Icons.open_in_new_rounded),
        onPressed: _openInBrowser,
      ),
      IconButton(
        tooltip: 'Fullscreen',
        constraints: const BoxConstraints(
          minWidth: DesignTokens.minTouchTarget,
          minHeight: DesignTokens.minTouchTarget,
        ),
        icon: const Icon(Icons.fullscreen_rounded),
        onPressed: () => setState(() => _isFullscreen = true),
      ),
    ];

    return Scaffold(
      appBar: (_isFullscreen || widget.embedded)
          ? null
          : TbAppBar(
              title: Row(
                children: [
                  Hero(
                    tag: 'dashboard-${widget.dashboardId}',
                    child: titleBadge,
                  ),
                  const SizedBox(width: DesignTokens.spacing8),
                  Expanded(
                    child: Text(
                      titleText,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.titleMedium?.copyWith(
                        color: scheme.onSurface,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              actions: actionButtons,
            ),
      floatingActionButton: _isFullscreen
          ? FloatingActionButton.small(
              tooltip: 'Exit fullscreen',
              onPressed: () => setState(() => _isFullscreen = false),
              child: const Icon(Icons.fullscreen_exit_rounded),
            )
          : null,
      body: SafeArea(
        child: dashboardAsync.when(
          loading: () => const SingleChildScrollView(
            padding: DesignTokens.paddingMedium,
            child: TbShimmerList(itemCount: 3),
          ),
          error: (error, _) => TbEmptyState(
            icon: TbIconKind.dashboardTile,
            title: 'Failed to load',
            subtitle: error is TbFailure ? error.message : null,
            actionLabel: 'Retry',
            isError: true,
            onAction: () =>
                ref.invalidate(dashboardDetailsProvider(widget.dashboardId)),
          ),
          data: (dashboard) {
            final EntityId? entityId = isDemo
                ? (dashboard.resolveStaticTelemetryEntity() ??
                      EntityId(
                        entityType: EntityType.dashboard,
                        id: dashboard.info.id,
                      ))
                : ref
                      .watch(
                        dashboardTelemetryEntityProvider(widget.dashboardId),
                      )
                      .valueOrNull;

            if (entityId == null) {
              return const SingleChildScrollView(
                padding: DesignTokens.paddingMedium,
                child: TbShimmerList(itemCount: 3),
              );
            }

            final latestAsync = ref.watch(
              entityLatestTelemetryProvider(entityId),
            );
            final latestTelemetry = latestAsync.valueOrNull;
            final historyAsync = ref.watch(
              entityTelemetryHistoryProvider(entityId),
            );
            final history =
                historyAsync.valueOrNull ?? const <String, List<TbTsPoint>>{};

            _syncStableKeys(<String>{
              ...?latestTelemetry?.keys,
              ...history.keys,
            });

            final liveTelemetry = (isDemo || _liveKeys.isNotEmpty)
                ? ref
                      .watch(
                        liveEntityTelemetryProvider((
                          id: entityId,
                          keys: _liveKeys,
                        )),
                      )
                      .valueOrNull
                : null;

            final metricCards = _buildMetricEntries(
              dashboard: dashboard,
              latestTelemetry: latestTelemetry,
              liveTelemetry: liveTelemetry,
              history: history,
            );

            return CustomScrollView(
              slivers: [
                SliverPadding(
                  padding: DesignTokens.paddingMedium,
                  sliver: SliverList(
                    delegate: SliverChildListDelegate([
                      if (widget.embedded && !_isFullscreen) ...[
                        Row(
                          children: [
                            titleBadge,
                            const SizedBox(width: DesignTokens.spacing8),
                            Expanded(
                              child: Text(
                                dashboard.info.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: textTheme.titleMedium?.copyWith(
                                  color: scheme.onSurface,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            ...actionButtons,
                          ],
                        ),
                        const SizedBox(height: DesignTokens.spacing12),
                      ],
                      _StatusAndWindowBar(
                        isDemo: isDemo,
                        isLiveActive: isLiveActive,
                        timeWindow: _timeWindow,
                        onSelectWindow: (w) => _selectTimeWindow(w, entityId),
                      ),
                      const SizedBox(height: DesignTokens.spacing16),
                      if (metricCards.isEmpty && latestAsync.isLoading)
                        const TbShimmerList(itemCount: 2)
                      else if (metricCards.isEmpty)
                        TbEmptyState(
                          icon: TbIconKind.dashboardTile,
                          title: 'Web dashboard',
                          actionLabel: 'Open in browser',
                          onAction: _openInBrowser,
                        )
                      else
                        LayoutBuilder(
                          builder: (context, constraints) {
                            final cols = constraints.maxWidth >= 520 ? 2 : 1;
                            final gap = DesignTokens.spacing12;
                            final cardWidth =
                                (constraints.maxWidth - gap * (cols - 1)) /
                                cols;

                            return Wrap(
                              spacing: gap,
                              runSpacing: gap,
                              children: [
                                for (var i = 0; i < metricCards.length; i++)
                                  SizedBox(
                                    width: cardWidth,
                                    child: TbStaggeredEntry(
                                      index: i,
                                      child: _TelemetryMetricCard(
                                        entry: metricCards[i],
                                        isLoadingHistory:
                                            historyAsync.isLoading,
                                      ),
                                    ),
                                  ),
                              ],
                            );
                          },
                        ),
                    ]),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  List<_DashboardMetricVm> _buildMetricEntries({
    required TbDashboard dashboard,
    required Map<String, TbTsPoint>? latestTelemetry,
    required Map<String, TbTsPoint>? liveTelemetry,
    required Map<String, List<TbTsPoint>> history,
  }) {
    final result = <_DashboardMetricVm>[];
    final seenKeys = <String>{};

    // Include dashboard summary metrics first (Demo or metadata metrics).
    for (final entry in dashboard.info.metrics.entries) {
      final normalizedKey = entry.key.toLowerCase();
      seenKeys.add(normalizedKey);
      final series = _findMatchingSeries(normalizedKey, history);
      result.add(
        _DashboardMetricVm(
          key: entry.key,
          label: entry.key,
          value: entry.value,
          series: series,
        ),
      );
    }

    // Merge REST latest telemetry overridden by live WebSocket telemetry points.
    final combinedTelemetry = <String, TbTsPoint>{
      ...?latestTelemetry,
      ...?liveTelemetry,
    };
    for (final entry in combinedTelemetry.entries) {
      final norm = entry.key.toLowerCase();
      if (seenKeys.any((k) => k.contains(norm) || norm.contains(k))) {
        continue;
      }
      seenKeys.add(norm);
      result.add(
        _DashboardMetricVm(
          key: entry.key,
          label: entry.key,
          value: entry.value.displayValue,
          series: _findMatchingSeries(norm, history),
        ),
      );
    }

    // Fallback: surface history keys directly if live/static metrics are empty.
    if (result.isEmpty && history.isNotEmpty) {
      for (final entry in history.entries) {
        final lastPoint = entry.value.lastOrNull;
        final nums = entry.value
            .map((p) => p.numericValue)
            .whereType<double>()
            .toList(growable: false);
        result.add(
          _DashboardMetricVm(
            key: entry.key,
            label: entry.key,
            value: lastPoint?.displayValue ?? '—',
            series: nums,
          ),
        );
      }
    }

    return result;
  }

  List<double> _findMatchingSeries(
    String normalizedKey,
    Map<String, List<TbTsPoint>> history,
  ) {
    for (final entry in history.entries) {
      final hKey = entry.key.toLowerCase();
      if (hKey == normalizedKey ||
          normalizedKey.contains(hKey) ||
          hKey.contains(normalizedKey)) {
        return entry.value
            .map((p) => p.numericValue)
            .whereType<double>()
            .toList(growable: false);
      }
    }
    final firstSeries = history.values.firstOrNull;
    if (firstSeries == null) return const [];
    return firstSeries
        .map((p) => p.numericValue)
        .whereType<double>()
        .toList(growable: false);
  }
}

class _StatusAndWindowBar extends StatelessWidget {
  const _StatusAndWindowBar({
    required this.isDemo,
    required this.isLiveActive,
    required this.timeWindow,
    required this.onSelectWindow,
  });

  final bool isDemo;
  final bool isLiveActive;
  final DashboardTimeWindow timeWindow;
  final ValueChanged<DashboardTimeWindow> onSelectWindow;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: DesignTokens.spacing12,
      runSpacing: DesignTokens.spacing8,
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            LivePulseDot(
              active: isLiveActive,
              semanticLabel: isLiveActive ? 'Stream active' : 'Stream offline',
            ),
            const SizedBox(width: DesignTokens.spacing8),
            if (isDemo)
              TbStatusBadge.demo(compact: true)
            else
              TbStatusBadge.online(isLiveActive, compact: true),
          ],
        ),
        SegmentedButton<DashboardTimeWindow>(
          showSelectedIcon: false,
          selected: {timeWindow},
          onSelectionChanged: (selection) {
            if (selection.isNotEmpty) {
              onSelectWindow(selection.first);
            }
          },
          segments: [
            for (final preset in DashboardTimeWindow.values)
              ButtonSegment<DashboardTimeWindow>(
                value: preset,
                label: Text(preset.label),
              ),
          ],
        ),
      ],
    );
  }
}

class _DashboardMetricVm {
  const _DashboardMetricVm({
    required this.key,
    required this.label,
    required this.value,
    required this.series,
  });

  final String key;
  final String label;
  final String value;
  final List<double> series;
}

class _TelemetryMetricCard extends StatelessWidget {
  const _TelemetryMetricCard({
    required this.entry,
    required this.isLoadingHistory,
  });

  final _DashboardMetricVm entry;
  final bool isLoadingHistory;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      padding: DesignTokens.cardPadding,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: DesignTokens.borderRadiusXl,
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TbMetricPill(
            icon: TbIcons.kindForTelemetryKey(entry.key),
            label: entry.label,
            value: entry.value,
          ),
          const SizedBox(height: DesignTokens.spacing12),
          if (isLoadingHistory)
            const TbShimmer(height: 52)
          else if (entry.series.isNotEmpty)
            TbSparklineChart(
              values: entry.series,
              height: 52,
              semanticLabel: '${entry.label} trend',
            ),
        ],
      ),
    );
  }
}
