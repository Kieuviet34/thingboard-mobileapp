import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:thingsboard_democloud_app/config/themes/tb_text_styles.dart';
import 'package:thingsboard_democloud_app/core/mock/mock_data.dart';
import 'package:thingsboard_democloud_app/widgets/tb_app_bar.dart';

class DeviceDetailsPage extends ConsumerWidget {
  const DeviceDetailsPage({super.key, required this.deviceId});

  final String deviceId;

  static const _labelStyle = TextStyle(
    color: Color(0xFF757575),
    fontSize: 14,
    height: 20 / 14,
  );

  static const _valueStyle = TextStyle(
    color: Color(0xFF282828),
    fontSize: 14,
    height: 20 / 14,
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final devices = ref.watch(devicesProvider);
    final device = devices.firstWhere(
      (d) => d.id == deviceId,
      orElse: () => devices.first,
    );
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: TbAppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              device.name,
              style: const TextStyle(
                fontWeight: FontWeight.w500,
                fontSize: 16,
                height: 20 / 16,
              ),
            ),
            Text(
              'Device details',
              style: TextStyle(
                color: Colors.black.withAlpha((0.38 * 255).ceil()),
                fontSize: 12,
                fontWeight: FontWeight.normal,
                height: 16 / 12,
              ),
            ),
          ],
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('Name', style: _labelStyle),
          Text(device.name, style: _valueStyle),
          const SizedBox(height: 16),
          const Text('Type', style: _labelStyle),
          Text(device.type, style: _valueStyle),
          const SizedBox(height: 16),
          const Text('Label', style: _labelStyle),
          Text(device.label, style: _valueStyle),
          const SizedBox(height: 16),
          const Text('Status', style: _labelStyle),
          Text(
            device.active ? 'Active' : 'Inactive',
            style: _valueStyle.copyWith(
              color:
                  device.active
                      ? const Color(0xFF008A00)
                      : const Color(0xFFAFAFAF),
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 16),
          const Text('Assigned to customer', style: _labelStyle),
          Text(device.customerName, style: _valueStyle),
          const SizedBox(height: 24),
          const Divider(),
          const SizedBox(height: 16),
          Text('Latest Telemetry', style: TbTextStyles.titleXs),
          const SizedBox(height: 12),
          ...device.telemetry.entries.map(
            (e) => Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: Icon(Icons.timeline, color: theme.primaryColor),
                title: Text(e.key, style: TbTextStyles.bodyMedium),
                trailing: Text(
                  e.value,
                  style: TbTextStyles.labelLarge.copyWith(
                    color: theme.primaryColor,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
