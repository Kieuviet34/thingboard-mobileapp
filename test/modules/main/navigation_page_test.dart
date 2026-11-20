import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:thingsboard_democloud_app/config/themes/tb_theme.dart';
import 'package:thingsboard_democloud_app/core/api/controllers/server_config_controller.dart';
import 'package:thingsboard_democloud_app/main.dart';
import 'package:thingsboard_democloud_app/modules/main/navigation_page.dart';
import 'package:thingsboard_democloud_app/widgets/icons/tb_icons.dart';

import '../../helpers/fake_app_preferences.dart';
import '../../helpers/fake_secure_storage.dart';
import '../../helpers/fake_ws_channel.dart';
import '../../helpers/mock_dio_adapter.dart';

void main() {
  late MockDioAdapter adapter;
  late FakeSecureStorage storage;
  late FakeAppPreferences prefs;

  setUp(() {
    adapter = MockDioAdapter();
    storage = FakeSecureStorage();
    prefs = FakeAppPreferences();

    adapter.on(
      'GET',
      '/api/v2/alarms',
      (_) => MockDioAdapter.jsonResponse({
        'data': <Object>[],
        'totalPages': 0,
        'totalElements': 0,
        'hasNext': false,
      }),
    );
    adapter.on(
      'GET',
      '/api/notifications/unread/count',
      (_) => MockDioAdapter.jsonResponse({'totalUnreadCount': 0}),
    );
    adapter.on(
      'GET',
      '/api/noauth/userPasswordPolicy',
      (_) => MockDioAdapter.jsonResponse({'minimumLength': 6}),
    );
    adapter.on(
      'POST',
      '/api/noauth/oauth2Clients',
      (_) => MockDioAdapter.jsonResponse([]),
    );
  });

  List<Override> buildOverrides() => [
    tbStorageProvider.overrideWithValue(storage),
    tbAppPreferencesProvider.overrideWithValue(prefs),
    tbHttpClientAdapterProvider.overrideWithValue(adapter),
    wsChannelFactoryProvider.overrideWithValue((_) => FakeWebSocketChannel()),
  ];

  group('NavigationPage adaptive M3 shell', () {
    testWidgets(
      'renders bottom NavigationBar on compact (<600dp) and NavigationRail on medium (>=600dp)',
      (WidgetTester tester) async {
        await tester.pumpWidget(
          ProviderScope(
            overrides: buildOverrides(),
            child: MediaQuery(
              data: const MediaQueryData(size: Size(390, 844)),
              child: MaterialApp(
                theme: tbLightTheme(),
                home: const NavigationPage(child: Text('Body content')),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byType(NavigationBar), findsOneWidget);
        expect(find.byType(NavigationRail), findsNothing);
        expect(find.byType(TbIcon), findsWidgets);

        await tester.pumpWidget(
          ProviderScope(
            overrides: buildOverrides(),
            child: MediaQuery(
              data: const MediaQueryData(size: Size(720, 1024)),
              child: MaterialApp(
                theme: tbDarkTheme(),
                home: const NavigationPage(child: Text('Tablet body')),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byType(NavigationRail), findsOneWidget);
        expect(find.byType(NavigationBar), findsNothing);
        expect(find.text('Tablet body'), findsOneWidget);
      },
    );

    testWidgets(
      'StatefulShellRoute switches tabs, shows Demo badges, and returns to Home on back',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        final container = ProviderContainer(overrides: buildOverrides());

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: const ThingsboardDemoCloudApp(),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('try-demo-mode-button')));
        await tester.pumpAndSettle();

        expect(find.byType(NavigationBar), findsOneWidget);
        expect(find.byType(Badge), findsWidgets);

        await tester.tap(find.text('Alarms').last);
        await tester.pumpAndSettle();
        expect(find.text('Alarms'), findsWidgets);

        await tester.tap(find.text('Devices').last);
        await tester.pumpAndSettle();
        expect(find.text('Devices'), findsWidgets);

        await tester.tap(find.text('More').last);
        await tester.pumpAndSettle();
        expect(find.text('More'), findsWidgets);

        // System back from non-home tab returns to tab 0 (Home).
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(find.byType(NavigationBar), findsOneWidget);
        final navBar = tester.widget<NavigationBar>(find.byType(NavigationBar));
        expect(navBar.selectedIndex, 0);

        await tester.pumpWidget(const SizedBox.shrink());
        container.dispose();
        await tester.pump();
      },
    );
  });
}
