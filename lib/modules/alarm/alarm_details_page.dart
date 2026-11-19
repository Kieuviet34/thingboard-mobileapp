import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:thingsboard_democloud_app/config/themes/tb_text_styles.dart';
import 'package:thingsboard_democloud_app/core/mock/mock_data.dart';
import 'package:thingsboard_democloud_app/modules/alarm/widgets/user_info_avatar_widget.dart';
import 'package:thingsboard_democloud_app/widgets/tb_app_bar.dart';

class AlarmDetailsPage extends ConsumerStatefulWidget {
  const AlarmDetailsPage({super.key, required this.id});

  final String id;

  @override
  ConsumerState<AlarmDetailsPage> createState() => _AlarmDetailsPageState();
}

class _AlarmDetailsPageState extends ConsumerState<AlarmDetailsPage> {
  bool _detailsExpanded = true;
  final TextEditingController _commentController = TextEditingController();
  final DateFormat _startTimeFormat = DateFormat.yMd().add_jms();

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final alarms = ref.watch(alarmsProvider);
    final profile = ref.watch(userProfileProvider);
    final alarm = alarms.firstWhere(
      (a) => a.id == widget.id,
      orElse: () => alarms.first,
    );
    final theme = Theme.of(context);

    return Scaffold(
      appBar: TbAppBar(
        title: Text(
          alarm.type,
          style: TbTextStyles.titleXs.copyWith(
            color: Colors.black.withValues(alpha: .87),
          ),
        ),
      ),
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  vertical: 24,
                  horizontal: 16,
                ),
                child: Column(
                  spacing: 12,
                  children: [
                    _buildDetailsCard(context, alarm, theme),
                    _buildAssigneeCard(context, alarm, theme),
                    _buildActivityCard(context, alarm, profile, theme),
                  ],
                ),
              ),
            ),
            _buildControlButtons(context, alarm, theme),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailsCard(
    BuildContext context,
    MockAlarm alarm,
    ThemeData theme,
  ) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Colors.black.withValues(alpha: .12)),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: () => setState(() => _detailsExpanded = !_detailsExpanded),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Details',
                    style: TbTextStyles.labelLarge.copyWith(
                      color: Colors.black.withValues(alpha: .76),
                    ),
                  ),
                  Icon(
                    _detailsExpanded
                        ? Icons.expand_less
                        : Icons.expand_more,
                    color: Colors.black.withValues(alpha: .38),
                  ),
                ],
              ),
            ),
          ),
          if (_detailsExpanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                children: [
                  _buildDetailRow(context, 'Status', alarm.statusLabel),
                  _buildDetailRow(context, 'Type', alarm.type),
                  _buildDetailRow(
                    context,
                    'Severity',
                    alarm.severity.label,
                    detailsStyle: TbTextStyles.labelLarge.copyWith(
                      color: alarm.severity.color,
                    ),
                  ),
                  _buildDetailRow(context, 'Originator', alarm.originatorName),
                  _buildDetailRow(
                    context,
                    'Start time',
                    _startTimeFormat.format(alarm.createdTime),
                  ),
                  _buildDetailRow(
                    context,
                    'Duration',
                    _formatDuration(alarm.createdTime),
                    showDivider: alarm.dashboardId != null,
                  ),
                  if (alarm.dashboardId != null)
                    SizedBox(
                      width: double.infinity,
                      child: TextButton(
                        onPressed:
                            () => context.push(
                              '/dashboard/${alarm.dashboardId}',
                            ),
                        style: TextButton.styleFrom(
                          backgroundColor: theme.primaryColor.withValues(
                            alpha: .1,
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        child: Text(
                          'View Dashboard',
                          style: TbTextStyles.titleXs.copyWith(
                            color: theme.primaryColor,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(
    BuildContext context,
    String title,
    String details, {
    TextStyle? detailsStyle,
    bool showDivider = true,
  }) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TbTextStyles.bodyLarge.copyWith(
                color: Colors.black.withValues(alpha: .38),
              ),
            ),
            SizedBox(
              width: MediaQuery.of(context).size.width / 2,
              child: Text(
                details,
                textAlign: TextAlign.end,
                style:
                    detailsStyle ??
                    TbTextStyles.bodyLarge.copyWith(
                      color: Colors.black.withValues(alpha: .76),
                    ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        if (showDivider)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Divider(
              color: Colors.black.withValues(alpha: .05),
              thickness: 1,
              height: 0,
            ),
          ),
      ],
    );
  }

  Widget _buildAssigneeCard(
    BuildContext context,
    MockAlarm alarm,
    ThemeData theme,
  ) {
    final assignees = ['Unassigned', 'John Doe', 'Alice Smith', 'Bob Vance'];
    final current = alarm.assigneeName ?? 'Unassigned';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.black.withValues(alpha: .12)),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 8,
        children: [
          Text(
            'Assignee',
            style: TbTextStyles.labelLarge.copyWith(
              color: Colors.black.withValues(alpha: .76),
            ),
          ),
          DropdownButtonFormField<String>(
            initialValue: assignees.contains(current) ? current : 'Unassigned',
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              isDense: true,
            ),
            items:
                assignees
                    .map(
                      (name) => DropdownMenuItem(
                        value: name,
                        child: Text(name, style: TbTextStyles.bodyMedium),
                      ),
                    )
                    .toList(),
            onChanged: (value) {
              ref
                  .read(alarmsProvider.notifier)
                  .assign(
                    alarm.id,
                    value == 'Unassigned' ? null : value,
                  );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildActivityCard(
    BuildContext context,
    MockAlarm alarm,
    MockUserProfile profile,
    ThemeData theme,
  ) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Colors.black.withValues(alpha: .12)),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Activity',
                  style: TbTextStyles.labelLarge.copyWith(
                    color: Colors.black.withValues(alpha: .76),
                  ),
                ),
                Icon(
                  Icons.refresh_rounded,
                  color: Colors.black.withValues(alpha: .54),
                ),
              ],
            ),
          ),
          if (alarm.comments.isNotEmpty)
            Container(
              constraints: const BoxConstraints(maxHeight: 220),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: .03),
                border: Border(
                  top: BorderSide(color: Colors.black.withValues(alpha: .12)),
                  bottom: BorderSide(
                    color: Colors.black.withValues(alpha: .12),
                  ),
                ),
              ),
              child: ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.all(12),
                itemCount: alarm.comments.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final comment = alarm.comments[index];
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    spacing: 10,
                    children: [
                      UserInfoAvatarWidget(
                        shortName: comment.initials,
                        color:
                            comment.isSystem
                                ? Colors.blueGrey
                                : theme.primaryColor,
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              spacing: 8,
                              children: [
                                Text(
                                  comment.authorName,
                                  style: TbTextStyles.labelMedium,
                                ),
                                Text(
                                  DateFormat.Hm().format(comment.createdTime),
                                  style: TbTextStyles.bodySmall.copyWith(
                                    color: Colors.black54,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(
                              comment.text,
                              style: TbTextStyles.bodyMedium.copyWith(
                                fontStyle:
                                    comment.isSystem
                                        ? FontStyle.italic
                                        : FontStyle.normal,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Row(
              children: [
                UserInfoAvatarWidget(
                  shortName: profile.shortName,
                  color: theme.primaryColor,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _commentController,
                    decoration: InputDecoration(
                      hintText: 'Add a comment...',
                      isDense: true,
                      suffixIcon: IconButton(
                        icon: Icon(Icons.send, color: theme.primaryColor),
                        onPressed: () {
                          ref.read(alarmsProvider.notifier).addComment(
                            alarm.id,
                            _commentController.text,
                            profile.displayName,
                            profile.shortName,
                          );
                          _commentController.clear();
                        },
                      ),
                    ),
                    onSubmitted: (text) {
                      ref.read(alarmsProvider.notifier).addComment(
                        alarm.id,
                        text,
                        profile.displayName,
                        profile.shortName,
                      );
                      _commentController.clear();
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildControlButtons(
    BuildContext context,
    MockAlarm alarm,
    ThemeData theme,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0x1F000000))),
      ),
      child: Row(
        children: [
          Expanded(
            child: ElevatedButton(
              onPressed:
                  alarm.isActive
                      ? () async {
                        final confirm = await _confirmDialog(
                          context,
                          title: 'Clear Alarm',
                          message: 'Are you sure you want to clear Alarm?',
                        );
                        if (confirm == true) {
                          ref.read(alarmsProvider.notifier).clear(alarm.id);
                        }
                      }
                      : null,
              child: const Text('Clear'),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: ElevatedButton(
              onPressed:
                  !alarm.isAcknowledged
                      ? () async {
                        final confirm = await _confirmDialog(
                          context,
                          title: 'Acknowledge Alarm',
                          message:
                              'Are you sure you want to acknowledge Alarm?',
                        );
                        if (confirm == true) {
                          ref
                              .read(alarmsProvider.notifier)
                              .acknowledge(alarm.id);
                        }
                      }
                      : null,
              child: const Text('Acknowledge'),
            ),
          ),
        ],
      ),
    );
  }

  Future<bool?> _confirmDialog(
    BuildContext context, {
    required String title,
    required String message,
  }) {
    return showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Text(title),
            content: Text(message),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('NO'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('YES'),
              ),
            ],
          ),
    );
  }

  String _formatDuration(DateTime start) {
    final diff = DateTime.now().difference(start).abs();
    final parts = <String>[];
    if (diff.inDays > 0) parts.add('${diff.inDays} days');
    if (diff.inHours % 24 > 0) parts.add('${diff.inHours % 24} hours');
    if (diff.inMinutes % 60 > 0) parts.add('${diff.inMinutes % 60} minutes');
    parts.add('${diff.inSeconds % 60} seconds');
    return parts.join(' ');
  }
}
