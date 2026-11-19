import 'package:auto_size_text/auto_size_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:thingsboard_democloud_app/constants/assets_path.dart';
import 'package:thingsboard_democloud_app/core/mock/mock_data.dart';
import 'package:thingsboard_democloud_app/widgets/tb_app_bar.dart';

class DevicesMainPage extends ConsumerWidget {
  const DevicesMainPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profiles = ref.watch(deviceProfilesProvider);
    final devices = ref.watch(devicesProvider);
    final activeTotal = devices.where((d) => d.active).length;
    final inactiveTotal = devices.where((d) => !d.active).length;

    return Scaffold(
      appBar: TbAppBar(
        canGoBack: false,
        title: const Text('Devices'),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await Future<void>.delayed(const Duration(milliseconds: 300));
        },
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
                child: _AllDevicesCard(
                  activeCount: activeTotal,
                  inactiveCount: inactiveTotal,
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  childAspectRatio: 156 / 200,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                ),
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final profile = profiles[index];
                    return GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {
                        context.push(
                          '/devices/deviceList?deviceType=${Uri.encodeComponent(profile.name)}',
                        );
                      },
                      child: Container(
                        decoration: BoxDecoration(
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withAlpha(
                                (255 * 0.05).ceil(),
                              ),
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
                          child: _DeviceProfileCard(profile: profile),
                        ),
                      ),
                    );
                  },
                  childCount: profiles.length,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AllDevicesCard extends StatelessWidget {
  const _AllDevicesCard({
    required this.activeCount,
    required this.inactiveCount,
  });

  final int activeCount;
  final int inactiveCount;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => context.push('/devices/deviceList'),
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
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
          elevation: 0,
          child: Column(
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 12, 16, 15),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'All devices',
                      style: TextStyle(
                        fontWeight: FontWeight.w500,
                        fontSize: 14,
                        height: 20 / 14,
                      ),
                    ),
                    Icon(Icons.arrow_forward, size: 18),
                  ],
                ),
              ),
              const Divider(height: 1),
              Row(
                children: [
                  Flexible(
                    fit: FlexFit.tight,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap:
                          () => context.push('/devices/deviceList?active=true'),
                      child: Container(
                        height: 40,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: _buildDeviceCount(context, true, activeCount),
                      ),
                    ),
                  ),
                  const SizedBox(
                    width: 1,
                    height: 40,
                    child: VerticalDivider(width: 1),
                  ),
                  Flexible(
                    fit: FlexFit.tight,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap:
                          () =>
                              context.push('/devices/deviceList?active=false'),
                      child: Container(
                        height: 40,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: _buildDeviceCount(context, false, inactiveCount),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DeviceProfileCard extends StatelessWidget {
  const _DeviceProfileCard({required this.profile});

  final MockDeviceProfile profile;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: Column(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: SvgPicture.asset(
                width: 64,
                height: 64,
                ThingsboardImage.deviceProfilePlaceholder,
                semanticsLabel: 'Device profile',
              ),
            ),
          ),
          SizedBox(
            height: 44,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Center(
                child: AutoSizeText(
                  profile.name,
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
          const Divider(height: 1),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              context.push(
                '/devices/deviceList?active=true&deviceType=${Uri.encodeComponent(profile.name)}',
              );
            },
            child: _buildDeviceCount(context, true, profile.activeCount),
          ),
          const Divider(height: 1),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              context.push(
                '/devices/deviceList?active=false&deviceType=${Uri.encodeComponent(profile.name)}',
              );
            },
            child: _buildDeviceCount(context, false, profile.inactiveCount),
          ),
        ],
      ),
    );
  }
}

Widget _buildDeviceCount(BuildContext context, bool active, int count) {
  final Color color =
      active ? const Color(0xFF008A00) : const Color(0xFFAFAFAF);
  return Padding(
    padding: const EdgeInsets.all(12),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            Stack(
              children: [
                Icon(Icons.devices_other, size: 16, color: color),
                if (!active)
                  CustomPaint(
                    size: const Size.square(16),
                    painter: StrikeThroughPainter(color: color, offset: 2),
                  ),
              ],
            ),
            const SizedBox(width: 8.67),
            Text(
              active ? 'Active' : 'Inactive',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                height: 16 / 12,
                color: color,
              ),
            ),
            const SizedBox(width: 8.67),
            Text(
              count.toString(),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                height: 16 / 12,
                color: color,
              ),
            ),
          ],
        ),
        const Icon(Icons.chevron_right, size: 16, color: Color(0xFFACACAC)),
      ],
    ),
  );
}

class StrikeThroughPainter extends CustomPainter {
  StrikeThroughPainter({required this.color, this.offset = 0});
  final Color color;
  final double offset;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    paint.strokeWidth = 1.5;
    canvas.drawLine(
      Offset(offset, offset),
      Offset(size.width - offset, size.height - offset),
      paint,
    );
    paint.color = Colors.white;
    canvas.drawLine(
      const Offset(2, 0),
      Offset(size.width + 2, size.height),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant StrikeThroughPainter oldDelegate) {
    return color != oldDelegate.color;
  }
}
