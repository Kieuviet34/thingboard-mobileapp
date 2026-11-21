import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:thingsboard_democloud_app/config/themes/design_tokens.dart';
import 'package:thingsboard_democloud_app/config/themes/tb_theme.dart';
import 'package:thingsboard_democloud_app/core/api/controllers/server_config_controller.dart';
import 'package:thingsboard_democloud_app/main.dart';
import 'package:thingsboard_democloud_app/modules/main/navigation_page.dart';
import 'package:thingsboard_democloud_app/widgets/icons/tb_icons.dart';
import 'package:thingsboard_democloud_app/widgets/nav/tb_floating_nav_bar.dart';

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
      'renders floating nav bar on compact (<600dp) and NavigationRail on medium (>=600dp)',
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

        expect(find.byType(TbFloatingNavBar), findsOneWidget);
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
        expect(find.byType(TbFloatingNavBar), findsNothing);
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

        expect(find.byType(TbFloatingNavBar), findsOneWidget);
        expect(find.byType(Badge), findsWidgets);

        // Labels only show on the selected tab, so tap by tooltip.
        await tester.tap(find.byTooltip('Alarms'));
        await tester.pumpAndSettle();
        expect(find.text('Alarms'), findsWidgets);

        await tester.tap(find.byTooltip('Devices'));
        await tester.pumpAndSettle();
        expect(find.text('Devices'), findsWidgets);

        await tester.tap(find.byTooltip('More'));
        await tester.pumpAndSettle();
        expect(find.text('More'), findsWidgets);

        // System back from non-home tab returns to tab 0 (Home).
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(find.byType(TbFloatingNavBar), findsOneWidget);
        final navBar = tester.widget<TbFloatingNavBar>(
          find.byType(TbFloatingNavBar),
        );
        expect(navBar.selectedIndex, 0);

        await tester.pumpWidget(const SizedBox.shrink());
        container.dispose();
        await tester.pump();
      },
    );

    testWidgets('bottom sheets open above the floating nav, never under it', (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final container = ProviderContainer(overrides: buildOverrides());
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

      await tester.tap(find.byTooltip('More'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Profile & Settings'));
      await tester.pumpAndSettle();

      final pill = find.byKey(const Key('floating-nav-pill'));
      expect(pill.hitTestable(), findsOneWidget, reason: 'nav is usable');

      await tester.scrollUntilVisible(
        find.text('Network & Data Inspector'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Network & Data Inspector'));
      await tester.pumpAndSettle();
      expect(find.text('Data Traffic Inspector'), findsOneWidget);

      // A sheet on the tab's own navigator would leave the nav on top of its
      // bottom edge (and over its action buttons).
      expect(
        pill.hitTestable(),
        findsNothing,
        reason: 'sheet must cover the nav, not be covered by it',
      );
    });
  });

  group('NavigationPage responsive across device sizes', () {
    const windows = <String, Size>{
      'foldable cover 280x653': Size(280, 653),
      'small phone 320x568': Size(320, 568),
      'compact phone 360x640': Size(360, 640),
      'iPhone 375x667': Size(375, 667),
      'iPhone 390x844': Size(390, 844),
      'Pixel 412x915': Size(412, 915),
      'Pro Max 430x932': Size(430, 932),
      'large phone 599x900': Size(599, 900),
      'landscape phone 568x320': Size(568, 320),
      'landscape phone 667x375': Size(667, 375),
      'landscape phone 844x390': Size(844, 390),
      'tablet 768x1024': Size(768, 1024),
      'tablet 1024x768': Size(1024, 768),
    };
    const pillKey = Key('floating-nav-pill');

    for (final entry in windows.entries) {
      for (final textScale in const [1.0, 2.0]) {
        testWidgets('${entry.key} @ ${textScale}x text', (tester) async {
          final size = entry.value;
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1.0;
          tester.platformDispatcher.textScaleFactorTestValue = textScale;
          addTearDown(tester.view.reset);
          addTearDown(tester.platformDispatcher.clearAllTestValues);

          await tester.pumpWidget(
            ProviderScope(
              overrides: buildOverrides(),
              child: MaterialApp(
                theme: tbLightTheme(),
                home: const NavigationPage(child: Text('Body content')),
              ),
            ),
          );
          await tester.pumpAndSettle();

          // No RenderFlex overflow or layout exception at any size/scale.
          expect(tester.takeException(), isNull);

          if (size.width < DesignTokens.compactMaxWidth) {
            expect(find.byType(NavigationRail), findsNothing);

            final pill = tester.widget<Material>(find.byKey(pillKey));
            // Fully round (stadium) glass: translucent but still legible.
            expect(pill.shape, isA<StadiumBorder>());
            expect(pill.color!.a, closeTo(DesignTokens.navGlassOpacity, 0.01));

            final rect = tester.getRect(find.byKey(pillKey));
            expect(rect.height, DesignTokens.navBarHeight);
            expect(rect.left, greaterThanOrEqualTo(0));
            expect(rect.right, lessThanOrEqualTo(size.width));
            expect(rect.bottom, lessThanOrEqualTo(size.height));
            expect(
              rect.width,
              lessThanOrEqualTo(DesignTokens.floatingNavMaxWidth),
            );
          } else {
            expect(find.byType(TbFloatingNavBar), findsNothing);
            final rail = tester.widget<NavigationRail>(
              find.byType(NavigationRail),
            );
            // Expanded rail only on large windows, never on short landscape.
            expect(
              rail.extended,
              size.width >= DesignTokens.mediumMaxWidth &&
                  size.height >= DesignTokens.compactMinHeight,
            );
          }
        });
      }
    }
  });
}
