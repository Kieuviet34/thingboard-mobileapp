import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:thingsboard_democloud_app/config/themes/tb_text_styles.dart';
import 'package:thingsboard_democloud_app/core/api/client/tb_network_inspector.dart';
import 'package:thingsboard_democloud_app/widgets/icons/tb_icons.dart';

/// Modal dialog allowing engineers and testers to inspect outgoing and incoming
/// REST/WS payloads, headers, latency, and status codes in real time.
class TbNetworkInspectorDialog extends ConsumerStatefulWidget {
  const TbNetworkInspectorDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => const TbNetworkInspectorDialog(),
    );
  }

  @override
  ConsumerState<TbNetworkInspectorDialog> createState() =>
      _TbNetworkInspectorDialogState();
}

class _TbNetworkInspectorDialogState
    extends ConsumerState<TbNetworkInspectorDialog> {
  String _selectedFilter = 'ALL';
  String? _expandedId;

  Color _methodColor(String method, ColorScheme scheme) {
    return switch (method.toUpperCase()) {
      'GET' => Colors.blue,
      'POST' => Colors.green,
      'PUT' => Colors.orange,
      'DELETE' => Colors.red,
      _ => scheme.primary,
    };
  }

  Color _statusColor(int? statusCode, bool isError) {
    if (isError || (statusCode != null && statusCode >= 400)) {
      return Colors.red;
    }
    if (statusCode != null && statusCode >= 200 && statusCode < 300) {
      return Colors.green;
    }
    return Colors.amber;
  }

  @override
  Widget build(BuildContext context) {
    final entries = ref.watch(tbNetworkLogProvider);
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final filtered = entries.where((e) {
      if (_selectedFilter == 'ERRORS') return e.isError;
      if (_selectedFilter == 'GET') return e.method.toUpperCase() == 'GET';
      if (_selectedFilter == 'POST') return e.method.toUpperCase() == 'POST';
      return true;
    }).toList();

    return DraggableScrollableSheet(
      initialChildSize: 0.82,
      minChildSize: 0.45,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: scheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            border: Border.all(color: scheme.outlineVariant),
          ),
          child: Column(
            children: [
              // Drag Handle
              const SizedBox(height: 12),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: scheme.onSurfaceVariant.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 12),

              // Header
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    TbIcon(TbIconKind.gateway, size: 22, color: scheme.primary),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Data Traffic Inspector',
                            style: textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            '${entries.length} captured transactions',
                            style: textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Clear logs',
                      icon: const Icon(Icons.delete_sweep_outlined),
                      onPressed: () =>
                          ref.read(tbNetworkLogProvider.notifier).clear(),
                    ),
                    IconButton(
                      tooltip: 'Close',
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),

              // Filter Chips
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                // Scrolls sideways instead of overflowing on narrow/large-text.
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (final filter in ['ALL', 'GET', 'POST', 'ERRORS'])
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: FilterChip(
                            selected: _selectedFilter == filter,
                            label: Text(filter),
                            onSelected: (selected) {
                              if (selected) {
                                setState(() => _selectedFilter = filter);
                              }
                            },
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const Divider(height: 1),

              // List of Requests
              Expanded(
                child: filtered.isEmpty
                    ? Center(
                        child: Text(
                          entries.isEmpty
                              ? 'No network transactions recorded yet.\nMake requests or perform actions to inspect data.'
                              : 'No requests matching "$_selectedFilter"',
                          textAlign: TextAlign.center,
                          style: textTheme.bodyMedium?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      )
                    : ListView.separated(
                        controller: scrollController,
                        itemCount: filtered.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final item = filtered[index];
                          final isExpanded = _expandedId == item.id;
                          final methodColor = _methodColor(item.method, scheme);
                          final statusColor = _statusColor(
                            item.statusCode,
                            item.isError,
                          );

                          return InkWell(
                            onTap: () {
                              setState(() {
                                _expandedId = isExpanded ? null : item.id;
                              });
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 12,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      // Badges wrap onto a second line at large
                                      // text sizes instead of overflowing.
                                      Expanded(
                                        child: Wrap(
                                          spacing: 8,
                                          runSpacing: 4,
                                          crossAxisAlignment:
                                              WrapCrossAlignment.center,
                                          children: [
                                            // Method badge
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 6,
                                                    vertical: 2,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: methodColor.withValues(
                                                  alpha: 0.15,
                                                ),
                                                borderRadius:
                                                    BorderRadius.circular(6),
                                              ),
                                              child: Text(
                                                item.method,
                                                style: textTheme.labelSmall
                                                    ?.copyWith(
                                                      color: methodColor,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                    ),
                                              ),
                                            ),
                                            // Status badge
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 6,
                                                    vertical: 2,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: statusColor.withValues(
                                                  alpha: 0.15,
                                                ),
                                                borderRadius:
                                                    BorderRadius.circular(6),
                                              ),
                                              child: Text(
                                                item.statusCode != null
                                                    ? '${item.statusCode}'
                                                    : (item.isError
                                                          ? 'ERR'
                                                          : 'OK'),
                                                style: textTheme.labelSmall
                                                    ?.copyWith(
                                                      color: statusColor,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                    ),
                                              ),
                                            ),
                                            // Latency
                                            if (item.durationMs != null)
                                              Text(
                                                '${item.durationMs}ms',
                                                style:
                                                    TbTextStyles.tabular(
                                                      textTheme.labelSmall ??
                                                          const TextStyle(),
                                                    ).copyWith(
                                                      color: scheme
                                                          .onSurfaceVariant,
                                                    ),
                                              ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 8),

                                      // Time
                                      Text(
                                        '${item.timestamp.hour.toString().padLeft(2, '0')}:${item.timestamp.minute.toString().padLeft(2, '0')}:${item.timestamp.second.toString().padLeft(2, '0')}',
                                        style:
                                            TbTextStyles.tabular(
                                              textTheme.labelSmall ??
                                                  const TextStyle(),
                                            ).copyWith(
                                              color: scheme.onSurfaceVariant,
                                            ),
                                      ),
                                      const SizedBox(width: 4),
                                      Icon(
                                        isExpanded
                                            ? Icons.expand_less
                                            : Icons.expand_more,
                                        size: 18,
                                        color: scheme.onSurfaceVariant,
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    item.url,
                                    maxLines: isExpanded ? 5 : 1,
                                    overflow: isExpanded
                                        ? TextOverflow.visible
                                        : TextOverflow.ellipsis,
                                    style: textTheme.bodySmall?.copyWith(
                                      fontFamily: 'monospace',
                                    ),
                                  ),

                                  // Expanded Details
                                  if (isExpanded) ...[
                                    const SizedBox(height: 12),
                                    if (item.errorMessage != null) ...[
                                      Container(
                                        width: double.infinity,
                                        padding: const EdgeInsets.all(8),
                                        decoration: BoxDecoration(
                                          color: scheme.errorContainer,
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                        ),
                                        child: Text(
                                          'Error: ${item.errorMessage}',
                                          style: textTheme.bodySmall?.copyWith(
                                            color: scheme.onErrorContainer,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                    ],

                                    // Request Body Section
                                    _PayloadSection(
                                      title: 'REQUEST PAYLOAD',
                                      content: item.prettyRequestBody,
                                    ),
                                    const SizedBox(height: 8),

                                    // Response Body Section
                                    _PayloadSection(
                                      title: 'RESPONSE DATA',
                                      content: item.prettyResponseBody,
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _PayloadSection extends StatefulWidget {
  const _PayloadSection({required this.title, required this.content});

  final String title;
  final String content;

  @override
  State<_PayloadSection> createState() => _PayloadSectionState();
}

class _PayloadSectionState extends State<_PayloadSection> {
  Timer? _resetTimer;
  bool _copied = false;

  String get title => widget.title;
  String get content => widget.content;

  @override
  void dispose() {
    _resetTimer?.cancel();
    super.dispose();
  }

  /// Confirms on the button itself. A snackbar would be painted on the root
  /// Scaffold, i.e. underneath this root-navigator bottom sheet.
  void _copy() {
    Clipboard.setData(ClipboardData(text: content));
    _resetTimer?.cancel();
    setState(() => _copied = true);
    _resetTimer = Timer(const Duration(milliseconds: 1500), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.8,
                    color: scheme.primary,
                  ),
                ),
              ),
              IconButton(
                icon: Icon(
                  _copied ? Icons.check_rounded : Icons.copy_rounded,
                  size: 16,
                  color: _copied ? scheme.primary : null,
                ),
                visualDensity: VisualDensity.compact,
                tooltip: _copied ? 'Copied $title' : 'Copy $title',
                onPressed: _copy,
              ),
            ],
          ),
          const SizedBox(height: 4),
          SelectableText(
            content,
            style: textTheme.bodySmall?.copyWith(
              fontFamily: 'monospace',
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}
