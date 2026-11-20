import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:thingsboard_democloud_app/config/routes/router.dart';
import 'package:thingsboard_democloud_app/config/themes/design_tokens.dart';
import 'package:thingsboard_democloud_app/config/themes/tb_text_styles.dart';
import 'package:thingsboard_democloud_app/core/api/controllers/alarm_controller.dart';
import 'package:thingsboard_democloud_app/core/api/controllers/asset_controller.dart';
import 'package:thingsboard_democloud_app/core/api/controllers/device_controller.dart';
import 'package:thingsboard_democloud_app/core/api/controllers/rpc_controller.dart';
import 'package:thingsboard_democloud_app/core/api/controllers/server_config_controller.dart';
import 'package:thingsboard_democloud_app/core/api/controllers/telemetry_controller.dart';
import 'package:thingsboard_democloud_app/core/models/models.dart';
import 'package:thingsboard_democloud_app/widgets/icons/tb_icons.dart';
import 'package:thingsboard_democloud_app/widgets/tb_app_bar.dart';
import 'package:thingsboard_democloud_app/widgets/tb_empty_state.dart';
import 'package:thingsboard_democloud_app/widgets/tb_metric_pill.dart';
import 'package:thingsboard_democloud_app/widgets/tb_motion.dart';
import 'package:thingsboard_democloud_app/widgets/tb_shimmer.dart';
import 'package:thingsboard_democloud_app/widgets/tb_status_badge.dart';

enum _DeviceSection {
  telemetry('Telemetry', TbIconKind.temperature),
  attributes('Attributes', TbIconKind.attributesTag),
  rpc('RPC', TbIconKind.rpcCommand),
  alarms('Alarms', TbIconKind.navAlarms),
  info('Info', TbIconKind.relationsGraph);

  const _DeviceSection(this.label, this.icon);
  final String label;
  final TbIconKind icon;
}

enum _TelemetryWindow {
  hour1('1h', Duration(hours: 1)),
  hour24('24h', Duration(hours: 24)),
  day7('7d', Duration(days: 7));

  const _TelemetryWindow(this.label, this.duration);
  final String label;
  final Duration duration;
}

/// Material 3 Device Detail screen with Hero transition and 5 tabbed sections:
/// Telemetry, Attributes, RPC, Alarms, and Info.
class DeviceDetailsPage extends ConsumerStatefulWidget {
  const DeviceDetailsPage({
    super.key,
    required this.deviceId,
    this.embedded = false,
  });

  final String deviceId;
  final bool embedded;

  @override
  ConsumerState<DeviceDetailsPage> createState() => _DeviceDetailsPageState();
}

class _DeviceDetailsPageState extends ConsumerState<DeviceDetailsPage> {
  _DeviceSection _section = _DeviceSection.telemetry;
  _TelemetryWindow _window = _TelemetryWindow.hour24;
  TbAttributeScope _attrScope = TbAttributeScope.serverScope;
  bool _showCredentials = false;
  List<String> _liveKeys = const <String>[];

  EntityId get _entityId =>
      EntityId(entityType: EntityType.device, id: widget.deviceId);

  void _syncStableKeys(Iterable<String> nextKeys) {
    final sorted = nextKeys.toList()..sort();
    if (!listEquals(_liveKeys, sorted)) {
      _liveKeys = List<String>.unmodifiable(sorted);
    }
  }

  Future<void> _refreshSection() async {
    ref.invalidate(deviceDetailsProvider(widget.deviceId));
    switch (_section) {
      case _DeviceSection.telemetry:
        ref.invalidate(entityLatestTelemetryProvider(_entityId));
        ref.invalidate(entityTelemetryHistoryProvider(_entityId));
      case _DeviceSection.attributes:
        ref.invalidate(
          entityAttributesProvider((id: _entityId, scope: _attrScope)),
        );
      case _DeviceSection.rpc:
        ref.invalidate(persistentRpcsProvider(widget.deviceId));
      case _DeviceSection.alarms:
        await ref.read(alarmsListProvider(_entityId).notifier).refresh();
      case _DeviceSection.info:
        if (_showCredentials) {
          ref.invalidate(deviceCredentialsProvider(widget.deviceId));
        }
        ref.invalidate(
          entityRelationsProvider((entity: _entityId, outgoing: true)),
        );
        ref.invalidate(
          entityRelationsProvider((entity: _entityId, outgoing: false)),
        );
    }
  }

  Future<void> _selectWindow(_TelemetryWindow next) async {
    setState(() => _window = next);
    final now = DateTime.now().millisecondsSinceEpoch;
    final startTs = now - next.duration.inMilliseconds;
    await ref
        .read(entityTelemetryHistoryProvider(_entityId).notifier)
        .loadRange(
          TbTsHistoryQuery(
            entityId: _entityId,
            keys: _liveKeys,
            startTs: startTs,
            endTs: now,
          ),
        );
  }

  @override
  Widget build(BuildContext context) {
    final deviceAsync = ref.watch(deviceDetailsProvider(widget.deviceId));
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final titleText = deviceAsync.valueOrNull?.name ?? 'Device';

    return Scaffold(
      appBar: widget.embedded
          ? null
          : TbAppBar(
              title: Text(titleText),
              actions: [
                IconButton(
                  key: const Key('device-details-refresh-button'),
                  tooltip: 'Refresh device',
                  constraints: const BoxConstraints(
                    minWidth: DesignTokens.minTouchTarget,
                    minHeight: DesignTokens.minTouchTarget,
                  ),
                  icon: const Icon(Icons.refresh),
                  onPressed: _refreshSection,
                ),
              ],
            ),
      body: deviceAsync.when(
        loading: () => const SingleChildScrollView(
          padding: DesignTokens.paddingMedium,
          child: TbShimmerList(itemCount: 4),
        ),
        error: (err, _) => TbEmptyState(
          icon: TbIconKind.severityCritical,
          title: 'Failed to load device',
          subtitle: err is TbFailure ? err.message : err.toString(),
          isError: true,
          actionLabel: 'Retry',
          onAction: () =>
              ref.invalidate(deviceDetailsProvider(widget.deviceId)),
        ),
        data: (device) {
          final iconBox = Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: scheme.secondaryContainer,
              borderRadius: DesignTokens.borderRadiusMedium,
            ),
            alignment: Alignment.center,
            child: TbIcon(
              TbIcons.kindForDeviceType(device.type),
              size: DesignTokens.iconMedium,
              color: scheme.onSecondaryContainer,
              semanticLabel: device.type,
            ),
          );

          final heroIcon = widget.embedded
              ? iconBox
              : Hero(tag: 'device-${device.id}', child: iconBox);

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Concise device header strip
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  DesignTokens.spacing16,
                  DesignTokens.spacing12,
                  DesignTokens.spacing16,
                  DesignTokens.spacing8,
                ),
                child: Container(
                  padding: DesignTokens.cardPadding,
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerLow,
                    borderRadius: DesignTokens.borderRadiusLarge,
                    border: Border.all(color: scheme.outlineVariant),
                  ),
                  child: Row(
                    children: [
                      heroIcon,
                      const SizedBox(width: DesignTokens.spacing12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          spacing: DesignTokens.spacing2,
                          children: [
                            Text(
                              device.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              device.label.isNotEmpty
                                  ? '${device.type} · ${device.label}'
                                  : device.type,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: textTheme.bodySmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: DesignTokens.spacing8),
                      TbStatusBadge.online(device.active, compact: true),
                      if (widget.embedded) ...[
                        const SizedBox(width: DesignTokens.spacing4),
                        IconButton(
                          tooltip: 'Refresh device',
                          constraints: const BoxConstraints(
                            minWidth: DesignTokens.minTouchTarget,
                            minHeight: DesignTokens.minTouchTarget,
                          ),
                          icon: const Icon(Icons.refresh),
                          onPressed: _refreshSection,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              // Horizontally scrollable M3 SegmentedButton for 5 sections
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(
                  horizontal: DesignTokens.spacing16,
                  vertical: DesignTokens.spacing4,
                ),
                child: SegmentedButton<_DeviceSection>(
                  key: const Key('device-section-segmented'),
                  showSelectedIcon: false,
                  segments: [
                    for (final sec in _DeviceSection.values)
                      ButtonSegment<_DeviceSection>(
                        value: sec,
                        icon: TbIcon(sec.icon, size: DesignTokens.iconSmall),
                        label: Text(sec.label),
                      ),
                  ],
                  selected: {_section},
                  onSelectionChanged: (selection) {
                    if (selection.isNotEmpty) {
                      setState(() => _section = selection.first);
                    }
                  },
                ),
              ),
              const SizedBox(height: DesignTokens.spacing8),
              Expanded(
                child: switch (_section) {
                  _DeviceSection.telemetry => _TelemetrySection(
                    device: device,
                    entityId: _entityId,
                    window: _window,
                    onWindowSelected: _selectWindow,
                    syncKeys: _syncStableKeys,
                    stableKeys: _liveKeys,
                  ),
                  _DeviceSection.attributes => _AttributesSection(
                    entityId: _entityId,
                    scope: _attrScope,
                    onScopeChanged: (s) => setState(() => _attrScope = s),
                  ),
                  _DeviceSection.rpc => _RpcSection(deviceId: device.id),
                  _DeviceSection.alarms => _DeviceAlarmsSection(
                    entityId: _entityId,
                  ),
                  _DeviceSection.info => _DeviceInfoSection(
                    device: device,
                    entityId: _entityId,
                    showCredentials: _showCredentials,
                    onToggleCredentials: () =>
                        setState(() => _showCredentials = !_showCredentials),
                  ),
                },
              ),
            ],
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 1) TELEMETRY SECTION
// ---------------------------------------------------------------------------
class _TelemetrySection extends ConsumerWidget {
  const _TelemetrySection({
    required this.device,
    required this.entityId,
    required this.window,
    required this.onWindowSelected,
    required this.syncKeys,
    required this.stableKeys,
  });

  final TbDeviceInfo device;
  final EntityId entityId;
  final _TelemetryWindow window;
  final Future<void> Function(_TelemetryWindow next) onWindowSelected;
  final void Function(Iterable<String> keys) syncKeys;
  final List<String> stableKeys;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(serverConfigProvider.select((s) => s.mode));
    final latestAsync = ref.watch(entityLatestTelemetryProvider(entityId));
    final historyAsync = ref.watch(entityTelemetryHistoryProvider(entityId));

    final mergedKeys = <String>{
      ...device.telemetry.keys,
      if (latestAsync.valueOrNull != null) ...latestAsync.valueOrNull!.keys,
    };
    syncKeys(mergedKeys);

    final liveAsync = stableKeys.isEmpty
        ? const AsyncData<Map<String, TbTsPoint>>(<String, TbTsPoint>{})
        : ref.watch(
            liveEntityTelemetryProvider((id: entityId, keys: stableKeys)),
          );

    final combinedLatest = <String, String>{
      ...device.telemetry,
      if (latestAsync.valueOrNull != null)
        for (final entry in latestAsync.valueOrNull!.entries)
          entry.key: entry.value.displayValue,
      if (liveAsync.valueOrNull != null)
        for (final entry in liveAsync.valueOrNull!.entries)
          entry.key: entry.value.displayValue,
    };

    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(entityLatestTelemetryProvider(entityId));
        ref.invalidate(entityTelemetryHistoryProvider(entityId));
      },
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(
          DesignTokens.spacing16,
          0,
          DesignTokens.spacing16,
          DesignTokens.spacing24,
        ),
        itemCount: 3,
        itemBuilder: (context, index) {
          if (index == 0) {
            return Padding(
              padding: const EdgeInsets.only(bottom: DesignTokens.spacing12),
              child: Row(
                children: [
                  LivePulseDot(
                    active: device.active,
                    semanticLabel: device.active ? 'Live stream' : 'Offline',
                  ),
                  const SizedBox(width: DesignTokens.spacing4),
                  Expanded(
                    child: Text(
                      mode == SessionMode.demo ? 'Demo stream' : 'Live stream',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.labelMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Wrap(
                    spacing: DesignTokens.spacing4,
                    children: [
                      for (final w in _TelemetryWindow.values)
                        ChoiceChip(
                          key: Key('telemetry-window-${w.label}'),
                          label: Text(w.label),
                          selected: window == w,
                          onSelected: (_) => onWindowSelected(w),
                        ),
                    ],
                  ),
                ],
              ),
            );
          }
          if (index == 1) {
            if (latestAsync.isLoading && combinedLatest.isEmpty) {
              return const Padding(
                padding: EdgeInsets.only(bottom: DesignTokens.spacing12),
                child: TbShimmerList(itemCount: 1),
              );
            }
            if (combinedLatest.isEmpty) {
              return const Padding(
                padding: EdgeInsets.only(bottom: DesignTokens.spacing12),
                child: TbEmptyState(
                  icon: TbIconKind.temperature,
                  title: 'No telemetry yet',
                ),
              );
            }
            return Padding(
              padding: const EdgeInsets.only(bottom: DesignTokens.spacing16),
              child: Wrap(
                spacing: DesignTokens.spacing8,
                runSpacing: DesignTokens.spacing8,
                children: [
                  for (final entry in combinedLatest.entries)
                    TbMetricPill(
                      icon: TbIcons.kindForTelemetryKey(entry.key),
                      label: entry.key,
                      value: entry.value,
                    ),
                ],
              ),
            );
          }

          return historyAsync.when(
            loading: () => const TbShimmerList(itemCount: 2),
            error: (err, _) => TbEmptyState(
              icon: TbIconKind.severityCritical,
              title: 'History unavailable',
              subtitle: err is TbFailure ? err.message : err.toString(),
              isError: true,
              actionLabel: 'Retry',
              onAction: () => onWindowSelected(window),
            ),
            data: (seriesMap) {
              final numericSeries = <MapEntry<String, List<double>>>[
                for (final entry in seriesMap.entries)
                  if (entry.value.any((p) => p.numericValue != null))
                    MapEntry(
                      entry.key,
                      entry.value
                          .map((p) => p.numericValue)
                          .whereType<double>()
                          .toList(growable: false),
                    ),
              ];
              if (numericSeries.isEmpty) {
                return const TbEmptyState(
                  icon: TbIconKind.temperature,
                  title: 'No chart history',
                );
              }
              return Column(
                spacing: DesignTokens.spacing12,
                children: [
                  for (final series in numericSeries)
                    _SparklineCard(seriesKey: series.key, values: series.value),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

class _SparklineCard extends StatelessWidget {
  const _SparklineCard({required this.seriesKey, required this.values});

  final String seriesKey;
  final List<double> values;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final latest = values.isNotEmpty ? values.last : 0.0;
    final minVal = values.reduce((a, b) => a < b ? a : b);
    final maxVal = values.reduce((a, b) => a > b ? a : b);

    return Container(
      key: Key('sparkline-card-$seriesKey'),
      padding: DesignTokens.cardPadding,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: DesignTokens.borderRadiusLarge,
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: DesignTokens.spacing8,
        children: [
          Row(
            children: [
              TbIcon(
                TbIcons.kindForTelemetryKey(seriesKey),
                size: DesignTokens.iconSmall,
                color: scheme.primary,
              ),
              const SizedBox(width: DesignTokens.spacing8),
              Expanded(
                child: Text(
                  seriesKey,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Text(
                latest.toStringAsFixed(1),
                style: TbTextStyles.tabular(
                  textTheme.titleSmall ?? TbTextStyles.titleSmall,
                ).copyWith(color: scheme.primary, fontWeight: FontWeight.w700),
              ),
            ],
          ),
          TbSparklineChart(
            values: values,
            height: 64,
            color: scheme.primary,
            semanticLabel: '$seriesKey trend chart',
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Min ${minVal.toStringAsFixed(1)}',
                style: TbTextStyles.tabular(
                  textTheme.labelSmall ?? TbTextStyles.labelSmall,
                ).copyWith(color: scheme.onSurfaceVariant),
              ),
              Text(
                'Max ${maxVal.toStringAsFixed(1)}',
                style: TbTextStyles.tabular(
                  textTheme.labelSmall ?? TbTextStyles.labelSmall,
                ).copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 2) ATTRIBUTES SECTION
// ---------------------------------------------------------------------------
class _AttributesSection extends ConsumerWidget {
  const _AttributesSection({
    required this.entityId,
    required this.scope,
    required this.onScopeChanged,
  });

  final EntityId entityId;
  final TbAttributeScope scope;
  final ValueChanged<TbAttributeScope> onScopeChanged;

  Future<void> _openEditor(
    BuildContext context,
    WidgetRef ref, {
    TbAttributeEntry? existing,
  }) async {
    final saved = await showModalBottomSheet<({String key, Object value})>(
      context: context,
      isScrollControlled: true,
      builder: (sheetCtx) =>
          _AttributeEditorSheet(scope: scope, existing: existing),
    );

    if (saved == null || !context.mounted) return;
    try {
      await ref
          .read(entityAttributesProvider((id: entityId, scope: scope)).notifier)
          .saveAttributes(<String, dynamic>{saved.key: saved.value});
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('Saved ${saved.key}')));
    } catch (e) {
      if (!context.mounted) return;
      final msg = e is TbFailure ? e.message : e.toString();
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  Future<void> _deleteAttribute(
    BuildContext context,
    WidgetRef ref,
    String key,
  ) async {
    try {
      await ref
          .read(entityAttributesProvider((id: entityId, scope: scope)).notifier)
          .deleteAttributes([key]);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('Deleted $key')));
    } catch (e) {
      if (!context.mounted) return;
      final msg = e is TbFailure ? e.message : e.toString();
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final attrsAsync = ref.watch(
      entityAttributesProvider((id: entityId, scope: scope)),
    );
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: DesignTokens.spacing16,
          ),
          child: Row(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    spacing: DesignTokens.spacing8,
                    children: [
                      for (final s in TbAttributeScope.values)
                        ChoiceChip(
                          key: Key('attr-scope-${s.wireValue}'),
                          label: Text(s.label),
                          selected: scope == s,
                          onSelected: (_) => onScopeChanged(s),
                        ),
                    ],
                  ),
                ),
              ),
              if (scope.isWritableViaRest) ...[
                const SizedBox(width: DesignTokens.spacing8),
                FilledButton.tonalIcon(
                  key: const Key('attr-add-button'),
                  onPressed: () => _openEditor(context, ref),
                  icon: const Icon(Icons.add, size: DesignTokens.iconSmall),
                  label: const Text('Add'),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: DesignTokens.spacing8),
        Expanded(
          child: attrsAsync.when(
            loading: () => const SingleChildScrollView(
              padding: DesignTokens.paddingMedium,
              child: TbShimmerList(itemCount: 3),
            ),
            error: (err, _) => TbEmptyState(
              icon: TbIconKind.severityCritical,
              title: 'Attributes unavailable',
              subtitle: err is TbFailure ? err.message : err.toString(),
              isError: true,
              actionLabel: 'Retry',
              onAction: () => ref.invalidate(
                entityAttributesProvider((id: entityId, scope: scope)),
              ),
            ),
            data: (entries) {
              if (entries.isEmpty) {
                return TbEmptyState(
                  icon: TbIconKind.attributesTag,
                  title: 'No ${scope.label.toLowerCase()} attributes',
                  actionLabel: scope.isWritableViaRest ? 'Add attribute' : null,
                  onAction: scope.isWritableViaRest
                      ? () => _openEditor(context, ref)
                      : null,
                );
              }
              return ListView.builder(
                padding: const EdgeInsets.fromLTRB(
                  DesignTokens.spacing16,
                  0,
                  DesignTokens.spacing16,
                  DesignTokens.spacing24,
                ),
                itemCount: entries.length,
                itemBuilder: (context, index) {
                  final entry = entries[index];
                  return Padding(
                    padding: const EdgeInsets.only(
                      bottom: DesignTokens.spacing8,
                    ),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: DesignTokens.spacing12,
                        vertical: DesignTokens.spacing8,
                      ),
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerLow,
                        borderRadius: DesignTokens.borderRadiusMedium,
                        border: Border.all(color: scheme.outlineVariant),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  entry.key,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: textTheme.labelMedium?.copyWith(
                                    color: scheme.onSurfaceVariant,
                                  ),
                                ),
                                Text(
                                  entry.displayValue,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TbTextStyles.tabular(
                                    textTheme.bodyMedium ??
                                        TbTextStyles.bodyMedium,
                                  ).copyWith(fontWeight: FontWeight.w600),
                                ),
                              ],
                            ),
                          ),
                          if (scope.isWritableViaRest) ...[
                            IconButton(
                              key: Key('attr-edit-${entry.key}'),
                              tooltip: 'Edit ${entry.key}',
                              constraints: const BoxConstraints(
                                minWidth: DesignTokens.minTouchTarget,
                                minHeight: DesignTokens.minTouchTarget,
                              ),
                              icon: const Icon(Icons.edit_outlined),
                              onPressed: () =>
                                  _openEditor(context, ref, existing: entry),
                            ),
                            IconButton(
                              key: Key('attr-delete-${entry.key}'),
                              tooltip: 'Delete ${entry.key}',
                              constraints: const BoxConstraints(
                                minWidth: DesignTokens.minTouchTarget,
                                minHeight: DesignTokens.minTouchTarget,
                              ),
                              icon: Icon(
                                Icons.delete_outline,
                                color: scheme.error,
                              ),
                              onPressed: () =>
                                  _deleteAttribute(context, ref, entry.key),
                            ),
                          ],
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// 3) RPC SECTION
// ---------------------------------------------------------------------------
class _RpcSection extends ConsumerStatefulWidget {
  const _RpcSection({required this.deviceId});

  final String deviceId;

  @override
  ConsumerState<_RpcSection> createState() => _RpcSectionState();
}

class _RpcSectionState extends ConsumerState<_RpcSection> {
  final TextEditingController _methodController = TextEditingController(
    text: 'setState',
  );
  final TextEditingController _paramsController = TextEditingController(
    text: '{"enabled": true}',
  );
  bool _twoWay = true;
  bool _persistent = false;
  String? _validationError;

  @override
  void dispose() {
    _methodController.dispose();
    _paramsController.dispose();
    super.dispose();
  }

  Future<void> _sendRpc() async {
    final method = _methodController.text.trim();
    if (method.isEmpty) {
      setState(() => _validationError = 'Method name required');
      return;
    }

    Map<String, dynamic> params = const {};
    final rawParams = _paramsController.text.trim();
    if (rawParams.isNotEmpty) {
      try {
        final decoded = jsonDecode(rawParams);
        if (decoded is! Map<String, dynamic>) {
          setState(() => _validationError = 'Params must be a JSON object');
          return;
        }
        params = decoded;
      } catch (_) {
        setState(() => _validationError = 'Invalid JSON params');
        return;
      }
    }

    setState(() => _validationError = null);
    await ref
        .read(rpcControllerProvider(widget.deviceId).notifier)
        .execute(
          request: TbRpcRequest(
            method: method,
            params: params,
            persistent: _persistent,
          ),
          twoWay: _twoWay,
        );
  }

  @override
  Widget build(BuildContext context) {
    final rpcAsync = ref.watch(rpcControllerProvider(widget.deviceId));
    final persistentAsync = ref.watch(persistentRpcsProvider(widget.deviceId));
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(
        DesignTokens.spacing16,
        0,
        DesignTokens.spacing16,
        DesignTokens.spacing24,
      ),
      itemCount: 3,
      itemBuilder: (context, index) {
        if (index == 0) {
          return Padding(
            padding: const EdgeInsets.only(bottom: DesignTokens.spacing12),
            child: Material(
              color: scheme.surfaceContainerLow,
              shape: RoundedRectangleBorder(
                borderRadius: DesignTokens.borderRadiusLarge,
                side: BorderSide(color: scheme.outlineVariant),
              ),
              clipBehavior: Clip.antiAlias,
              child: Padding(
                padding: DesignTokens.cardPadding,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: DesignTokens.spacing12,
                  children: [
                    SegmentedButton<bool>(
                      key: const Key('rpc-mode-segmented'),
                      showSelectedIcon: false,
                      segments: const [
                        ButtonSegment<bool>(
                          value: true,
                          label: Text('Two-way'),
                        ),
                        ButtonSegment<bool>(
                          value: false,
                          label: Text('One-way'),
                        ),
                      ],
                      selected: {_twoWay},
                      onSelectionChanged: (sel) =>
                          setState(() => _twoWay = sel.first),
                    ),
                    TextField(
                      key: const Key('rpc-method-input'),
                      controller: _methodController,
                      decoration: const InputDecoration(
                        labelText: 'Method',
                        isDense: true,
                      ),
                    ),
                    TextField(
                      key: const Key('rpc-params-input'),
                      controller: _paramsController,
                      maxLines: 3,
                      minLines: 1,
                      decoration: InputDecoration(
                        labelText: 'Params (JSON)',
                        errorText: _validationError,
                        isDense: true,
                      ),
                    ),
                    SwitchListTile(
                      key: const Key('rpc-persistent-switch'),
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Persistent'),
                      value: _persistent,
                      onChanged: (v) => setState(() => _persistent = v),
                    ),
                    FilledButton.icon(
                      key: const Key('rpc-send-button'),
                      onPressed: rpcAsync.isLoading ? null : _sendRpc,
                      icon: TbIcon(
                        TbIconKind.rpcCommand,
                        size: DesignTokens.iconSmall,
                        color: scheme.onPrimary,
                      ),
                      label: const Text('Send RPC'),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        if (index == 1) {
          return rpcAsync.when(
            loading: () => const Padding(
              padding: EdgeInsets.only(bottom: DesignTokens.spacing12),
              child: TbShimmerList(itemCount: 1),
            ),
            error: (err, _) => Container(
              key: const Key('rpc-error-banner'),
              margin: const EdgeInsets.only(bottom: DesignTokens.spacing12),
              padding: DesignTokens.paddingSmall,
              decoration: BoxDecoration(
                color: scheme.errorContainer,
                borderRadius: DesignTokens.borderRadiusMedium,
              ),
              child: Text(
                err is TbFailure ? err.message : err.toString(),
                style: textTheme.bodySmall?.copyWith(
                  color: scheme.onErrorContainer,
                ),
              ),
            ),
            data: (response) {
              if (response == null) return const SizedBox.shrink();
              final pretty = const JsonEncoder.withIndent(
                '  ',
              ).convert(response);
              return Container(
                key: const Key('rpc-response-card'),
                margin: const EdgeInsets.only(bottom: DesignTokens.spacing12),
                padding: DesignTokens.cardPadding,
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest,
                  borderRadius: DesignTokens.borderRadiusMedium,
                  border: Border.all(color: scheme.outlineVariant),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: DesignTokens.spacing4,
                  children: [
                    Text(
                      'Response',
                      style: textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    SelectableText(
                      pretty,
                      style: TbTextStyles.tabular(
                        textTheme.bodySmall ?? TbTextStyles.bodySmall,
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: DesignTokens.spacing8,
          children: [
            Text(
              'Persistent RPCs',
              style: textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            persistentAsync.when(
              loading: () => const TbShimmerList(itemCount: 2),
              error: (err, _) => TbEmptyState(
                icon: TbIconKind.severityCritical,
                title: 'Queue unavailable',
                subtitle: err is TbFailure ? err.message : err.toString(),
                isError: true,
                actionLabel: 'Retry',
                onAction: () =>
                    ref.invalidate(persistentRpcsProvider(widget.deviceId)),
              ),
              data: (paged) {
                if (paged.items.isEmpty) {
                  return const TbEmptyState(
                    icon: TbIconKind.rpcCommand,
                    title: 'No persistent RPCs',
                  );
                }
                return Column(
                  spacing: DesignTokens.spacing8,
                  children: [
                    for (final rpc in paged.items)
                      Container(
                        key: Key('persistent-rpc-${rpc.id}'),
                        padding: DesignTokens.paddingSmall,
                        decoration: BoxDecoration(
                          color: scheme.surfaceContainerLow,
                          borderRadius: DesignTokens.borderRadiusMedium,
                          border: Border.all(color: scheme.outlineVariant),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                spacing: DesignTokens.spacing4,
                                children: [
                                  Text(
                                    '${rpc.request['method'] ?? 'RPC'}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: textTheme.titleSmall?.copyWith(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  TbStatusBadge(
                                    label: rpc.status.wireValue,
                                    icon: TbIconKind.rpcCommand,
                                    tone: rpc.status == RpcStatus.successful
                                        ? TbStatusTone.online
                                        : rpc.status == RpcStatus.failed ||
                                              rpc.status == RpcStatus.timeout
                                        ? TbStatusTone.critical
                                        : TbStatusTone.warning,
                                    compact: true,
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              key: Key('cancel-rpc-${rpc.id}'),
                              tooltip: 'Delete persistent RPC',
                              constraints: const BoxConstraints(
                                minWidth: DesignTokens.minTouchTarget,
                                minHeight: DesignTokens.minTouchTarget,
                              ),
                              icon: Icon(
                                Icons.delete_outline,
                                color: scheme.error,
                              ),
                              onPressed: () => ref
                                  .read(
                                    persistentRpcsProvider(
                                      widget.deviceId,
                                    ).notifier,
                                  )
                                  .deleteRpc(rpc.id),
                            ),
                          ],
                        ),
                      ),
                  ],
                );
              },
            ),
          ],
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// 4) DEVICE ALARMS SECTION
// ---------------------------------------------------------------------------
class _DeviceAlarmsSection extends ConsumerWidget {
  const _DeviceAlarmsSection({required this.entityId});

  final EntityId entityId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final alarmsAsync = ref.watch(alarmsListProvider(entityId));
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return alarmsAsync.when(
      loading: () => const SingleChildScrollView(
        padding: DesignTokens.paddingMedium,
        child: TbShimmerList(itemCount: 3),
      ),
      error: (err, _) => TbEmptyState(
        icon: TbIconKind.severityCritical,
        title: 'Alarms unavailable',
        subtitle: err is TbFailure ? err.message : err.toString(),
        isError: true,
        actionLabel: 'Retry',
        onAction: () =>
            ref.read(alarmsListProvider(entityId).notifier).refresh(),
      ),
      data: (paged) {
        if (paged.items.isEmpty) {
          return const TbEmptyState(
            icon: TbIconKind.statusCleared,
            title: 'No device alarms',
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(
            DesignTokens.spacing16,
            0,
            DesignTokens.spacing16,
            DesignTokens.spacing24,
          ),
          itemCount: paged.items.length,
          itemBuilder: (context, index) {
            final alarm = paged.items[index];
            return Padding(
              padding: const EdgeInsets.only(bottom: DesignTokens.spacing8),
              child: Material(
                color: scheme.surfaceContainerLow,
                shape: RoundedRectangleBorder(
                  borderRadius: DesignTokens.borderRadiusLarge,
                  side: BorderSide(color: scheme.outlineVariant),
                ),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () => GoRouter.maybeOf(
                    context,
                  )?.push(AppRoutes.alarmDetailsPath(alarm.id)),
                  child: Padding(
                    padding: DesignTokens.cardPadding,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      spacing: DesignTokens.spacing8,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                alarm.type,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            const SizedBox(width: DesignTokens.spacing8),
                            alarm.cleared
                                ? TbStatusBadge.cleared(compact: true)
                                : TbStatusBadge.severity(
                                    alarm.severity,
                                    compact: true,
                                  ),
                          ],
                        ),
                        Wrap(
                          spacing: DesignTokens.spacing8,
                          children: [
                            if (!alarm.acknowledged)
                              TextButton.icon(
                                key: Key('device-alarm-ack-${alarm.id}'),
                                style: TextButton.styleFrom(
                                  minimumSize: const Size(
                                    DesignTokens.minTouchTarget,
                                    DesignTokens.minTouchTarget,
                                  ),
                                ),
                                onPressed: () => ref
                                    .read(alarmsListProvider(entityId).notifier)
                                    .acknowledge(alarm.id),
                                icon: const Icon(
                                  Icons.check,
                                  size: DesignTokens.iconSmall,
                                ),
                                label: const Text('Ack'),
                              ),
                            if (!alarm.cleared)
                              TextButton.icon(
                                key: Key('device-alarm-clear-${alarm.id}'),
                                style: TextButton.styleFrom(
                                  minimumSize: const Size(
                                    DesignTokens.minTouchTarget,
                                    DesignTokens.minTouchTarget,
                                  ),
                                ),
                                onPressed: () => ref
                                    .read(alarmsListProvider(entityId).notifier)
                                    .clear(alarm.id),
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
          },
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// 5) INFO SECTION (Profile, Owner, Credentials w/ 403 safe notice, Relations)
// ---------------------------------------------------------------------------
class _DeviceInfoSection extends ConsumerWidget {
  const _DeviceInfoSection({
    required this.device,
    required this.entityId,
    required this.showCredentials,
    required this.onToggleCredentials,
  });

  final TbDeviceInfo device;
  final EntityId entityId;
  final bool showCredentials;
  final VoidCallback onToggleCredentials;

  static final DateFormat _dateFormat = DateFormat('yyyy-MM-dd HH:mm');

  TbIconKind _iconForEntity(EntityType type) => switch (type) {
    EntityType.asset => TbIconKind.assetBuilding,
    EntityType.customer => TbIconKind.customerOrg,
    EntityType.dashboard => TbIconKind.dashboardTile,
    _ => TbIconKind.sensorNode,
  };

  void _navigateToEntity(BuildContext context, EntityId target) {
    final router = GoRouter.maybeOf(context);
    if (router == null) return;
    switch (target.entityType) {
      case EntityType.device:
        router.push(AppRoutes.deviceDetailsPath(target.id));
      case EntityType.asset:
        router.push(AppRoutes.assetDetailsPath(target.id));
      case EntityType.customer:
        router.push(AppRoutes.customerDetailsPath(target.id));
      case EntityType.dashboard:
        router.push(AppRoutes.dashboardDetailsPath(target.id));
      default:
        break;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final outgoingAsync = ref.watch(
      entityRelationsProvider((entity: entityId, outgoing: true)),
    );
    final incomingAsync = ref.watch(
      entityRelationsProvider((entity: entityId, outgoing: false)),
    );
    final credsAsync = showCredentials
        ? ref.watch(deviceCredentialsProvider(device.id))
        : null;

    final createdStr = device.createdTime > 0
        ? _dateFormat.format(
            DateTime.fromMillisecondsSinceEpoch(device.createdTime),
          )
        : '—';

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(
        DesignTokens.spacing16,
        0,
        DesignTokens.spacing16,
        DesignTokens.spacing24,
      ),
      itemCount: 3,
      itemBuilder: (context, index) {
        if (index == 0) {
          return Container(
            margin: const EdgeInsets.only(bottom: DesignTokens.spacing12),
            padding: DesignTokens.cardPadding,
            decoration: BoxDecoration(
              color: scheme.surfaceContainerLow,
              borderRadius: DesignTokens.borderRadiusLarge,
              border: Border.all(color: scheme.outlineVariant),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: DesignTokens.spacing8,
              children: [
                Text(
                  'Device metadata',
                  style: textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                _InfoKvRow(label: 'Profile', value: device.type),
                _InfoKvRow(
                  label: 'Label',
                  value: device.label.isNotEmpty ? device.label : '—',
                ),
                _InfoKvRow(
                  label: 'Owner',
                  value: device.ownerName.isNotEmpty ? device.ownerName : '—',
                ),
                _InfoKvRow(label: 'Created', value: createdStr),
              ],
            ),
          );
        }

        if (index == 1) {
          return Container(
            margin: const EdgeInsets.only(bottom: DesignTokens.spacing12),
            padding: DesignTokens.cardPadding,
            decoration: BoxDecoration(
              color: scheme.surfaceContainerLow,
              borderRadius: DesignTokens.borderRadiusLarge,
              border: Border.all(color: scheme.outlineVariant),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: DesignTokens.spacing8,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Credentials',
                        style: textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    TextButton(
                      key: const Key('toggle-credentials-button'),
                      style: TextButton.styleFrom(
                        minimumSize: const Size(
                          DesignTokens.minTouchTarget,
                          DesignTokens.minTouchTarget,
                        ),
                      ),
                      onPressed: onToggleCredentials,
                      child: Text(showCredentials ? 'Hide' : 'Show'),
                    ),
                  ],
                ),
                if (credsAsync != null)
                  credsAsync.when(
                    loading: () => const TbShimmer(height: 24),
                    error: (err, _) {
                      final isForbidden =
                          err is TbFailure &&
                          err.type == TbFailureType.permissionDenied;
                      return Container(
                        key: const Key('credentials-error-notice'),
                        padding: DesignTokens.paddingSmall,
                        decoration: BoxDecoration(
                          color: scheme.errorContainer,
                          borderRadius: DesignTokens.borderRadiusMedium,
                        ),
                        child: Text(
                          isForbidden
                              ? 'Restricted — insufficient permissions'
                              : (err is TbFailure
                                    ? err.message
                                    : err.toString()),
                          style: textTheme.bodySmall?.copyWith(
                            color: scheme.onErrorContainer,
                          ),
                        ),
                      );
                    },
                    data: (creds) => Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                creds.credentialsType,
                                style: textTheme.labelSmall?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                              Text(
                                creds.credentialsId,
                                key: const Key('credentials-id-text'),
                                style: TbTextStyles.tabular(
                                  textTheme.bodyMedium ??
                                      TbTextStyles.bodyMedium,
                                ).copyWith(fontWeight: FontWeight.w600),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: 'Copy credentials',
                          constraints: const BoxConstraints(
                            minWidth: DesignTokens.minTouchTarget,
                            minHeight: DesignTokens.minTouchTarget,
                          ),
                          icon: const Icon(Icons.copy_outlined),
                          onPressed: () async {
                            await Clipboard.setData(
                              ClipboardData(text: creds.credentialsId),
                            );
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context)
                              ..hideCurrentSnackBar()
                              ..showSnackBar(
                                const SnackBar(
                                  content: Text('Credentials copied'),
                                ),
                              );
                          },
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          );
        }

        final combinedRelations = <({TbEntityRelationInfo rel, bool outgoing})>[
          if (outgoingAsync.valueOrNull != null)
            for (final r in outgoingAsync.valueOrNull!)
              (rel: r, outgoing: true),
          if (incomingAsync.valueOrNull != null)
            for (final r in incomingAsync.valueOrNull!)
              (rel: r, outgoing: false),
        ];

        return Material(
          color: scheme.surfaceContainerLow,
          shape: RoundedRectangleBorder(
            borderRadius: DesignTokens.borderRadiusLarge,
            side: BorderSide(color: scheme.outlineVariant),
          ),
          clipBehavior: Clip.antiAlias,
          child: Padding(
            padding: DesignTokens.cardPadding,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: DesignTokens.spacing8,
              children: [
                Text(
                  'Relations',
                  style: textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (outgoingAsync.isLoading && incomingAsync.isLoading)
                  const TbShimmerList(itemCount: 2)
                else if (combinedRelations.isEmpty)
                  Text(
                    'No linked entities',
                    style: textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  )
                else
                  for (final item in combinedRelations)
                    ListTile(
                      key: Key(
                        'relation-${item.outgoing ? item.rel.to.id : item.rel.from.id}',
                      ),
                      contentPadding: EdgeInsets.zero,
                      minTileHeight: DesignTokens.minTouchTarget,
                      leading: TbIcon(
                        _iconForEntity(
                          item.outgoing
                              ? item.rel.to.entityType
                              : item.rel.from.entityType,
                        ),
                        color: scheme.primary,
                      ),
                      title: Text(
                        item.outgoing
                            ? (item.rel.toName.isNotEmpty
                                  ? item.rel.toName
                                  : item.rel.to.id)
                            : (item.rel.fromName.isNotEmpty
                                  ? item.rel.fromName
                                  : item.rel.from.id),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        '${item.outgoing ? '→' : '←'} ${item.rel.type}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => _navigateToEntity(
                        context,
                        item.outgoing ? item.rel.to : item.rel.from,
                      ),
                    ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _AttributeEditorSheet extends StatefulWidget {
  const _AttributeEditorSheet({required this.scope, this.existing});

  final TbAttributeScope scope;
  final TbAttributeEntry? existing;

  @override
  State<_AttributeEditorSheet> createState() => _AttributeEditorSheetState();
}

class _AttributeEditorSheetState extends State<_AttributeEditorSheet> {
  late final TextEditingController _keyController;
  late final TextEditingController _valueController;

  @override
  void initState() {
    super.initState();
    _keyController = TextEditingController(text: widget.existing?.key ?? '');
    _valueController = TextEditingController(
      text: widget.existing?.displayValue ?? '',
    );
  }

  @override
  void dispose() {
    _keyController.dispose();
    _valueController.dispose();
    super.dispose();
  }

  Object _parseAttrValue(String raw) {
    if (raw == 'true') return true;
    if (raw == 'false') return false;
    final asNum = num.tryParse(raw);
    if (asNum != null) return asNum;
    return raw;
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        DesignTokens.spacing16,
        DesignTokens.spacing16,
        DesignTokens.spacing16,
        bottomInset + DesignTokens.spacing16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: DesignTokens.spacing12,
        children: [
          Text(
            widget.existing == null
                ? 'Add ${widget.scope.label} attribute'
                : 'Edit ${widget.existing!.key}',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
          TextField(
            key: const Key('attr-key-input'),
            controller: _keyController,
            readOnly: widget.existing != null,
            decoration: const InputDecoration(labelText: 'Key'),
          ),
          TextField(
            key: const Key('attr-value-input'),
            controller: _valueController,
            decoration: const InputDecoration(labelText: 'Value'),
          ),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: DesignTokens.spacing8,
            children: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
              FilledButton(
                key: const Key('attr-save-button'),
                onPressed: () {
                  final k = _keyController.text.trim();
                  final raw = _valueController.text.trim();
                  if (k.isEmpty) return;
                  final Object parsed = _parseAttrValue(raw);
                  Navigator.of(context).pop((key: k, value: parsed));
                },
                child: const Text('Save'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _InfoKvRow extends StatelessWidget {
  const _InfoKvRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Row(
      children: [
        Expanded(
          flex: 2,
          child: Text(
            label,
            style: textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ),
        const SizedBox(width: DesignTokens.spacing8),
        Expanded(
          flex: 3,
          child: Text(
            value,
            textAlign: TextAlign.end,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TbTextStyles.tabular(
              textTheme.bodyMedium ?? TbTextStyles.bodyMedium,
            ).copyWith(fontWeight: FontWeight.w500),
          ),
        ),
      ],
    );
  }
}
