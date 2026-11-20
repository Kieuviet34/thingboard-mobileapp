import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:thingsboard_democloud_app/core/mock/mock_data.dart';

void main() {
  group('Mock data parity regressions', () {
    test(
      'MockAlarm.copyWith(clearAssignee: true) and AlarmsStateNotifier.assign(id, null) clear assigneeName',
      () {
        final container = ProviderContainer();
        addTearDown(container.dispose);

        final before = container.read(alarmsProvider);
        final assignedAlarm = before.firstWhere((a) => a.id == 'alarm-1');
        expect(assignedAlarm.assigneeName, isNotNull);

        container.read(alarmsProvider.notifier).assign('alarm-1', null);
        final after = container.read(alarmsProvider);
        final updated = after.firstWhere((a) => a.id == 'alarm-1');
        expect(updated.assigneeName, isNull);
      },
    );

    test(
      'deviceProfilesProvider activeCount & inactiveCount match devicesProvider',
      () {
        final container = ProviderContainer();
        addTearDown(container.dispose);

        final devices = container.read(devicesProvider);
        final profiles = container.read(deviceProfilesProvider);

        for (final profile in profiles) {
          final matching = devices
              .where((d) => d.type == profile.name)
              .toList();
          final expectedActive = matching.where((d) => d.active).length;
          final expectedInactive = matching.where((d) => !d.active).length;

          expect(
            profile.activeCount,
            expectedActive,
            reason: '${profile.name} activeCount should match devicesProvider',
          );
          expect(
            profile.inactiveCount,
            expectedInactive,
            reason:
                '${profile.name} inactiveCount should match devicesProvider',
          );
        }
      },
    );
  });
}
