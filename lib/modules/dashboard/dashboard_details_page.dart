import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:thingsboard_democloud_app/config/themes/app_colors.dart';
import 'package:thingsboard_democloud_app/config/themes/tb_text_styles.dart';
import 'package:thingsboard_democloud_app/constants/app_constants.dart';
import 'package:thingsboard_democloud_app/core/mock/mock_data.dart';
import 'package:thingsboard_democloud_app/widgets/tb_app_bar.dart';

class DashboardDetailsPage extends ConsumerStatefulWidget {
  const DashboardDetailsPage({super.key, required this.dashboardId});

  final String dashboardId;

  @override
  ConsumerState<DashboardDetailsPage> createState() =>
      _DashboardDetailsPageState();
}

class _DashboardDetailsPageState extends ConsumerState<DashboardDetailsPage> {
  bool _isFullscreen = false;

  @override
  Widget build(BuildContext context) {
    final dashboards = ref.watch(dashboardsProvider);
    final dashboard = dashboards.firstWhere(
      (d) => d.id == widget.dashboardId,
      orElse: () => dashboards.first,
    );
    final theme = Theme.of(context);
    final entries = dashboard.metrics.entries.toList();

    return Scaffold(
      appBar:
          _isFullscreen
              ? null
              : TbAppBar(
                title: Text(dashboard.title, style: TbTextStyles.titleXs),
                actions: [
                  IconButton(
                    icon: const Icon(Icons.fullscreen),
                    onPressed: () => setState(() => _isFullscreen = true),
                  ),
                ],
              ),
      floatingActionButton:
          _isFullscreen
              ? FloatingActionButton.small(
                backgroundColor: theme.primaryColor,
                onPressed: () => setState(() => _isFullscreen = false),
                child: const Icon(Icons.fullscreen_exit, color: Colors.white),
              )
              : null,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: 6,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Flexible(
                          child: Text(
                            dashboard.title,
                            style: TbTextStyles.titleSmall,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: theme.primaryColor.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            Uri.parse(
                              ThingsboardAppConstants.thingsBoardApiEndpoint,
                            ).host,
                            style: TbTextStyles.bodySmall.copyWith(
                              color: theme.primaryColor,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                    Text(
                      dashboard.description,
                      style: TbTextStyles.bodyMedium.copyWith(
                        color: AppColors.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 1.5,
              ),
              itemCount: entries.length,
              itemBuilder: (context, index) {
                final entry = entries[index];
                return Card(
                  margin: EdgeInsets.zero,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                entry.key,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TbTextStyles.bodySmall.copyWith(
                                  color: AppColors.textTertiary,
                                ),
                              ),
                            ),
                            Icon(
                              Icons.sensors,
                              size: 18,
                              color: theme.primaryColor,
                            ),
                          ],
                        ),
                        Text(
                          entry.value,
                          style: TbTextStyles.titleMedium.copyWith(
                            color: theme.primaryColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
