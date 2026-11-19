import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:thingsboard_democloud_app/config/themes/design_tokens.dart';
import 'package:thingsboard_democloud_app/config/themes/tb_text_styles.dart';
import 'package:thingsboard_democloud_app/core/mock/mock_data.dart';
import 'package:thingsboard_democloud_app/widgets/tb_app_bar.dart';
import 'package:thingsboard_democloud_app/widgets/tb_app_search_bar.dart';

class AlarmsPage extends ConsumerStatefulWidget {
  const AlarmsPage({super.key, this.searchMode = false});

  final bool searchMode;

  @override
  ConsumerState<AlarmsPage> createState() => _AlarmsPageState();
}

class _AlarmsPageState extends ConsumerState<AlarmsPage> {
  final PageController _pageController = PageController();
  String _searchText = '';
  Set<AlarmStatusFilter> _committedStatuses = {AlarmStatusFilter.active};
  Set<AlarmSeverityType> _committedSeverities = {};
  Set<AlarmStatusFilter> _draftStatuses = {AlarmStatusFilter.active};
  Set<AlarmSeverityType> _draftSeverities = {};
  bool _filtersChanged = false;

  bool get _hasActiveFilters =>
      _committedSeverities.isNotEmpty ||
      !(_committedStatuses.length == 1 &&
          _committedStatuses.contains(AlarmStatusFilter.active));

  List<MockAlarm> _filterAlarms(List<MockAlarm> all) {
    return all.where((alarm) {
      if (_searchText.isNotEmpty) {
        final q = _searchText.toLowerCase();
        final matches =
            alarm.type.toLowerCase().contains(q) ||
            alarm.originatorName.toLowerCase().contains(q) ||
            alarm.severity.label.toLowerCase().contains(q);
        if (!matches) return false;
      }
      if (!widget.searchMode) {
        if (_committedStatuses.isNotEmpty) {
          bool statusMatch = false;
          if (_committedStatuses.contains(AlarmStatusFilter.active) &&
              alarm.isActive) {
            statusMatch = true;
          }
          if (_committedStatuses.contains(AlarmStatusFilter.cleared) &&
              !alarm.isActive) {
            statusMatch = true;
          }
          if (_committedStatuses.contains(AlarmStatusFilter.acknowledged) &&
              alarm.isAcknowledged) {
            statusMatch = true;
          }
          if (_committedStatuses.contains(AlarmStatusFilter.unacknowledged) &&
              !alarm.isAcknowledged) {
            statusMatch = true;
          }
          if (!statusMatch) return false;
        }
        if (_committedSeverities.isNotEmpty &&
            !_committedSeverities.contains(alarm.severity)) {
          return false;
        }
      }
      return true;
    }).toList();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final alarms = _filterAlarms(ref.watch(alarmsProvider));

    if (widget.searchMode) {
      return Scaffold(
        appBar: TbAppSearchBar(
          searchHint: 'Search alarms',
          onSearch: (text) => setState(() => _searchText = text),
        ),
        body: _buildAlarmsList(alarms),
      );
    }

    return PageView(
      controller: _pageController,
      physics: const NeverScrollableScrollPhysics(),
      children: [
        Scaffold(
          appBar: TbAppBar(
            canGoBack: false,
            title: Text('Alarms', style: TbTextStyles.titleXs),
            actions: [
              Stack(
                children: [
                  IconButton(
                    icon: const Icon(Icons.filter_list),
                    onPressed: () {
                      setState(() {
                        _draftStatuses = Set.of(_committedStatuses);
                        _draftSeverities = Set.of(_committedSeverities);
                        _filtersChanged = false;
                      });
                      _pageController.animateToPage(
                        1,
                        duration: const Duration(milliseconds: 350),
                        curve: Curves.easeInOut,
                      );
                    },
                  ),
                  if (_hasActiveFilters)
                    Positioned(
                      right: 13,
                      top: 13,
                      child: Container(
                        height: 8,
                        width: 8,
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.white),
                          borderRadius: BorderRadius.circular(16),
                          color: Theme.of(context).primaryColor,
                        ),
                      ),
                    ),
                ],
              ),
              IconButton(
                icon: const Icon(Icons.search),
                onPressed: () => context.push('/alarms/search'),
              ),
            ],
          ),
          body: _buildAlarmsList(alarms),
        ),
        _buildFilterPage(context),
      ],
    );
  }

  Widget _buildAlarmsList(List<MockAlarm> alarms) {
    if (alarms.isEmpty) {
      return Center(
        child: Text(
          'No alarms found',
          style: TbTextStyles.bodyLarge.copyWith(
            color: Colors.black.withValues(alpha: 0.54),
          ),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: () async {
        await Future<void>.delayed(const Duration(milliseconds: 300));
      },
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: alarms.length,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final alarm = alarms[index];
          return Card(
            margin: EdgeInsets.zero,
            elevation: 1,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(4),
            ),
            child: InkWell(
              onTap: () => context.push('/alarms/alarmDetails/${alarm.id}'),
              child: AlarmCard(alarm: alarm),
            ),
          );
        },
      ),
    );
  }

  Widget _buildFilterPage(BuildContext context) {
    return Scaffold(
      appBar: TbAppBar(
        title: const Text('Filters'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            _pageController.animateToPage(
              0,
              duration: const Duration(milliseconds: 350),
              curve: Curves.easeInOut,
            );
          },
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    spacing: 16,
                    children: [
                      _buildFilterBlock<AlarmStatusFilter>(
                        title: 'Alarm status list',
                        items: AlarmStatusFilter.values,
                        selected: _draftStatuses,
                        labelBuilder: (item) => item.label,
                        onToggle: (item) {
                          setState(() {
                            if (_draftStatuses.contains(item)) {
                              _draftStatuses.remove(item);
                            } else {
                              _draftStatuses.add(item);
                            }
                            _filtersChanged = true;
                          });
                        },
                      ),
                      _buildFilterBlock<AlarmSeverityType>(
                        title: 'Alarm severity list',
                        items: AlarmSeverityType.values,
                        selected: _draftSeverities,
                        labelBuilder: (item) => item.label,
                        onToggle: (item) {
                          setState(() {
                            if (_draftSeverities.contains(item)) {
                              _draftSeverities.remove(item);
                            } else {
                              _draftSeverities.add(item);
                            }
                            _filtersChanged = true;
                          });
                        },
                      ),
                    ],
                  ),
                ),
              ),
              Row(
                children: [
                  TextButton(
                    onPressed: () {
                      setState(() {
                        _draftStatuses = {AlarmStatusFilter.active};
                        _draftSeverities = {};
                        _committedStatuses = {AlarmStatusFilter.active};
                        _committedSeverities = {};
                        _filtersChanged = false;
                      });
                    },
                    child: const Text('Reset'),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () {
                      _pageController.animateToPage(
                        0,
                        duration: const Duration(milliseconds: 350),
                        curve: Curves.easeInOut,
                      );
                    },
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed:
                        _filtersChanged
                            ? () {
                              setState(() {
                                _committedStatuses = Set.of(_draftStatuses);
                                _committedSeverities = Set.of(_draftSeverities);
                                _filtersChanged = false;
                              });
                              _pageController.animateToPage(
                                0,
                                duration: const Duration(milliseconds: 350),
                                curve: Curves.easeInOut,
                              );
                            }
                            : null,
                    child: const Text('Update'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFilterBlock<T>({
    required String title,
    required List<T> items,
    required Set<T> selected,
    required String Function(T) labelBuilder,
    required ValueChanged<T> onToggle,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.black.withValues(alpha: 0.12)),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 12,
        children: [
          Text(
            title,
            style: TbTextStyles.labelLarge.copyWith(
              color: Colors.black.withValues(alpha: 0.76),
            ),
          ),
          Wrap(
            runSpacing: 8,
            spacing: 8,
            children:
                items.map((item) {
                  final isSelected = selected.contains(item);
                  return FilledButton.icon(
                    onPressed: () => onToggle(item),
                    label: Text(
                      labelBuilder(item),
                      style:
                          !isSelected
                              ? TextStyle(
                                color: Colors.black.withValues(alpha: 0.38),
                                fontWeight: FontWeight.w400,
                                fontSize: 13,
                              )
                              : const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w500,
                                fontSize: 13,
                              ),
                    ),
                    icon:
                        !isSelected
                            ? const SizedBox.shrink()
                            : const Icon(Icons.check, size: 18),
                    style: FilledButton.styleFrom(
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      padding: const EdgeInsets.only(
                        top: 6,
                        bottom: 6,
                        left: 12,
                        right: 20,
                      ),
                      minimumSize: const Size(0, DesignTokens.buttonHeightSmall),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                      backgroundColor:
                          !isSelected
                              ? Colors.black.withValues(alpha: 0.06)
                              : null,
                    ),
                  );
                }).toList(),
          ),
        ],
      ),
    );
  }
}

class AlarmCard extends StatelessWidget {
  const AlarmCard({super.key, required this.alarm});
  final MockAlarm alarm;

  static final _entityDateFormat = DateFormat('yyyy-MM-dd');

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(4),
          bottomLeft: Radius.circular(4),
        ),
        border: Border(
          left: BorderSide(color: alarm.severity.color, width: 4),
        ),
      ),
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Flexible(
                      fit: FlexFit.tight,
                      child: Text(
                        alarm.type,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TbTextStyles.labelLarge,
                      ),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      _entityDateFormat.format(alarm.createdTime),
                      style: TbTextStyles.bodyMedium.copyWith(
                        color: Colors.black.withValues(alpha: .54),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Flexible(
                      fit: FlexFit.tight,
                      child: Text(
                        alarm.originatorName,
                        style: TbTextStyles.bodyMedium.copyWith(
                          color: Colors.black.withValues(alpha: .54),
                        ),
                      ),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      alarm.severity.label,
                      style: TbTextStyles.labelMedium.copyWith(
                        color: alarm.severity.color,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Divider(
            height: 24,
            thickness: 1,
            color: Colors.black.withValues(alpha: .05),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Flexible(
                  fit: FlexFit.tight,
                  child: Text(
                    alarm.statusLabel,
                    style: TbTextStyles.bodyMedium.copyWith(
                      color: Colors.black.withValues(alpha: .76),
                    ),
                  ),
                ),
                CircleAvatar(
                  radius: 16,
                  backgroundColor: Theme.of(
                    context,
                  ).primaryColor.withValues(alpha: .06),
                  child: IconButton(
                    icon: Icon(
                      Icons.more_vert,
                      size: 18,
                      color: Theme.of(context).primaryColor,
                    ),
                    padding: const EdgeInsets.all(7.0),
                    onPressed:
                        () => context.push('/alarms/alarmDetails/${alarm.id}'),
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
