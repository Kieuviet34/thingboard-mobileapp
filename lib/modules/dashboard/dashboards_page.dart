import 'package:auto_size_text/auto_size_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:thingsboard_democloud_app/constants/assets_path.dart';
import 'package:thingsboard_democloud_app/core/mock/mock_data.dart';
import 'package:thingsboard_democloud_app/widgets/tb_app_bar.dart';

class DashboardsPage extends ConsumerWidget {
  const DashboardsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dashboards = ref.watch(dashboardsProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: TbAppBar(
        canGoBack: false,
        elevation: 8,
        title: Center(
          child: SizedBox(
            height: 24,
            child: SvgPicture.asset(
              ThingsboardImage.thingsBoardWithTitle,
              colorFilter: ColorFilter.mode(
                theme.primaryColor,
                BlendMode.srcIn,
              ),
              semanticsLabel: 'ThingsBoard Logo',
            ),
          ),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await Future<void>.delayed(const Duration(milliseconds: 400));
        },
        child: SafeArea(
          child: GridView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              childAspectRatio: 156 / 150,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
            ),
            itemCount: dashboards.length,
            itemBuilder: (context, index) {
              final dashboard = dashboards[index];
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  context.push('/dashboard/${dashboard.id}');
                },
                child: Container(
                  decoration: BoxDecoration(
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withAlpha((255 * 0.05).ceil()),
                        blurRadius: 6.0,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Card(
                    margin: EdgeInsets.zero,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(4),
                    ),
                    elevation: 0,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: Column(
                        children: [
                          Expanded(
                            child: SizedBox.expand(
                              child: FittedBox(
                                clipBehavior: Clip.hardEdge,
                                fit: BoxFit.cover,
                                child: SvgPicture.asset(
                                  ThingsboardImage.dashboardPlaceholder,
                                  colorFilter: ColorFilter.mode(
                                    theme.primaryColor,
                                    BlendMode.overlay,
                                  ),
                                  semanticsLabel: 'Dashboard',
                                ),
                              ),
                            ),
                          ),
                          const Divider(height: 1),
                          SizedBox(
                            height: 44,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                              ),
                              child: Center(
                                child: AutoSizeText(
                                  dashboard.title,
                                  textAlign: TextAlign.center,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w500,
                                    fontSize: 14,
                                    height: 20 / 14,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
