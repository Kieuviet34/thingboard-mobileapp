import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:thingsboard_democloud_app/config/routes/router.dart';
import 'package:thingsboard_democloud_app/core/api/controllers/server_config_controller.dart';
import 'package:thingsboard_democloud_app/main.dart';

import '../../helpers/fake_app_preferences.dart';
import '../../helpers/fake_secure_storage.dart';
import '../../helpers/fake_ws_channel.dart';
import '../../helpers/mock_dio_adapter.dart';

/// Every content screen, in Demo mode (no network), across phone / foldable /
/// landscape / tablet windows and large text: no overflow, no red error widget.
void main() {
  late MockDioAdapter adapter;

  setUp(() {
    adapter = MockDioAdapter()
      ..on(
        'GET',
        '/api/noauth/userPasswordPolicy',
        (_) => MockDioAdapter.jsonResponse({'minimumLength': 6}),
      )
      ..on(
        'POST',
        '/api/noauth/oauth2Clients',
        (_) => MockDioAdapter.jsonResponse([]),
      );
  });

  final routes = <String, String>{
    'home': AppRoutes.home,
    'dashboards': AppRoutes.dashboards,
    'alarms': AppRoutes.alarms,
    'alarm details': AppRoutes.alarmDetailsPath('alarm-1'),
    'devices': AppRoutes.devices,
    'device list': AppRoutes.deviceList,
    'device details': AppRoutes.deviceDetailsPath('dev-1'),
    'more': AppRoutes.more,
    'customers': AppRoutes.customers,
    'customer details': AppRoutes.customerDetailsPath('cust-1'),
    'assets': AppRoutes.assets,
    'asset details': AppRoutes.assetDetailsPath('asset-1'),
    'audit logs': AppRoutes.auditLogs,
    'notifications': AppRoutes.notifications,
    'profile': AppRoutes.profile,
  };

  // (name, size, text scale)
  const cases = <(String, Size, double)>[
    ('foldable cover 280x653', Size(280, 653), 1.0),
    ('small phone 320x568', Size(320, 568), 1.0),
    ('small phone 320x568 text 2.0x', Size(320, 568), 2.0),
    ('phone 360x640', Size(360, 640), 1.0),
    ('phone 390x844', Size(390, 844), 1.0),
    ('phone 390x844 text 2.0x', Size(390, 844), 2.0),
    ('large phone 430x932', Size(430, 932), 1.0),
    ('landscape 667x375', Size(667, 375), 1.0),
    ('tablet 768x1024', Size(768, 1024), 1.0),
    ('tablet 1024x768', Size(1024, 768), 1.0),
  ];

  for (final window in cases) {
    final (windowName, size, textScale) = window;
    group(windowName, () {
      for (final route in routes.entries) {
        testWidgets(route.key, (tester) async {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1.0;
          tester.platformDispatcher.textScaleFactorTestValue = textScale;
          addTearDown(tester.view.reset);
          addTearDown(tester.platformDispatcher.clearAllTestValues);

          final container = ProviderContainer(
            overrides: [
              tbStorageProvider.overrideWithValue(FakeSecureStorage()),
              tbAppPreferencesProvider.overrideWithValue(FakeAppPreferences()),
              tbHttpClientAdapterProvider.overrideWithValue(adapter),
              wsChannelFactoryProvider.overrideWithValue(
                (_) => FakeWebSocketChannel(),
              ),
            ],
          );
          addTearDown(container.dispose);

          await tester.pumpWidget(
            UncontrolledProviderScope(
              container: container,
              child: const ThingsboardDemoCloudApp(),
            ),
          );
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const Key('try-demo-mode-button')));
          await tester.pumpAndSettle();

          container.read(routerProvider).go(route.value);
          // Bounded frames: some screens legitimately animate forever (live
          // pulse, shimmer), so "settled" can never be reached.
          for (var i = 0; i < 12; i++) {
            await tester.pump(const Duration(milliseconds: 250));
          }

          expect(
            tester.takeException(),
            isNull,
            reason: '${route.key} @ $windowName must not throw or overflow',
          );
          expect(find.byType(ErrorWidget), findsNothing);
        });
      }
    });
  }
}
