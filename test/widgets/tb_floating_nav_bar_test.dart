import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thingsboard_democloud_app/config/themes/design_tokens.dart';
import 'package:thingsboard_democloud_app/config/themes/tb_theme.dart';
import 'package:thingsboard_democloud_app/widgets/icons/tb_icons.dart';
import 'package:thingsboard_democloud_app/widgets/nav/tb_floating_nav_bar.dart';

const _destinations = [
  TbNavDestination(label: 'Home', icon: TbIconKind.navHome),
  TbNavDestination(
    label: 'Alarms',
    icon: TbIconKind.navAlarms,
    badgeCount: 3,
    badgeSemantics: 'active',
  ),
  TbNavDestination(label: 'Devices', icon: TbIconKind.navDevices),
  TbNavDestination(label: 'More', icon: TbIconKind.navMore),
];

void main() {
  late ValueNotifier<int> selected;
  late List<int> picked;

  setUp(() {
    selected = ValueNotifier<int>(0);
    picked = <int>[];
  });

  Widget host({
    double width = 390,
    bool disableAnimations = false,
    bool highContrast = false,
  }) {
    return MediaQuery(
      data: MediaQueryData(
        size: const Size(400, 800),
        disableAnimations: disableAnimations,
        highContrast: highContrast,
      ),
      child: MaterialApp(
        theme: tbLightTheme(),
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: SizedBox(
              width: width,
              child: ValueListenableBuilder<int>(
                valueListenable: selected,
                builder: (_, value, _) => TbFloatingNavBar(
                  destinations: _destinations,
                  selectedIndex: value,
                  onSelected: (i) {
                    picked.add(i);
                    selected.value = i;
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void usePhone(WidgetTester tester) {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  testWidgets(
    'only the selected destination shows a label, to the right of its icon',
    (tester) async {
      usePhone(tester);
      await tester.pumpWidget(host());
      await tester.pumpAndSettle();

      expect(find.text('Home'), findsOneWidget);
      expect(find.text('Alarms'), findsNothing);
      expect(find.text('Devices'), findsNothing);

      final label = tester.getRect(find.text('Home'));
      final icon = tester.getRect(find.byType(TbIcon).first);
      expect(
        label.left,
        greaterThan(icon.right),
        reason: 'label is right of icon',
      );
      expect(
        label.center.dy,
        closeTo(icon.center.dy, 2),
        reason: 'same baseline row',
      );
    },
  );

  testWidgets(
    'tapping a destination slides the label in and removes the old one',
    (tester) async {
      usePhone(tester);
      await tester.pumpWidget(host());
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Devices'));
      expect(picked, [2]);

      // The ticker starts on the frame after the rebuild; then advance
      // mid-flight so the new label is arriving while the old one fades.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));
      expect(find.text('Devices'), findsOneWidget);
      final earlyLeft = tester.getRect(find.text('Devices')).left;

      await tester.pumpAndSettle();
      expect(find.text('Home'), findsNothing);
      expect(find.text('Devices'), findsOneWidget);
      final settled = tester.getRect(find.text('Devices'));
      final icon = tester.getRect(find.byType(TbIcon).at(2));
      expect(settled.left, greaterThan(icon.right));
      // The label travelled (slid) rather than popping in at its final place.
      expect(settled.left, isNot(closeTo(earlyLeft, 0.5)));
    },
  );

  testWidgets('the whole highlighted pill of the selected tab is tappable', (
    tester,
  ) async {
    usePhone(tester);
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Devices'));
    await tester.pumpAndSettle();
    picked.clear();

    // Tapping the label (not just the icon) re-selects the tab, which the
    // shell uses to pop back to that tab's root.
    final label = tester.getRect(find.text('Devices'));
    await tester.tapAt(Offset(label.right - 2, label.center.dy));
    expect(picked, [2]);
    await tester.tapAt(label.center);
    expect(picked, [2, 2]);
  });

  testWidgets('jumping across tabs never flashes labels of tabs passed over', (
    tester,
  ) async {
    usePhone(tester);
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();

    // Home -> More skips Alarms and Devices.
    await tester.tap(find.byTooltip('More'));
    await tester.pump();
    for (var ms = 0; ms < 400; ms += 40) {
      await tester.pump(const Duration(milliseconds: 40));
      expect(find.text('Alarms'), findsNothing, reason: 'at ${ms}ms');
      expect(find.text('Devices'), findsNothing, reason: 'at ${ms}ms');
    }
    await tester.pumpAndSettle();
    expect(find.text('More'), findsOneWidget);
    expect(find.text('Home'), findsNothing);
  });

  testWidgets('honors disableAnimations: the switch is instant', (
    tester,
  ) async {
    usePhone(tester);
    await tester.pumpWidget(host(disableAnimations: true));
    await tester.pump();

    await tester.tap(find.byTooltip('More'));
    await tester.pump(); // a single frame, no settling

    expect(find.text('Home'), findsNothing);
    expect(find.text('More'), findsOneWidget);
  });

  testWidgets(
    'narrow window drops labels but keeps 48dp targets and tooltips',
    (tester) async {
      usePhone(tester);
      await tester.pumpWidget(host(width: 220));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      for (final name in ['Home', 'Alarms', 'Devices', 'More']) {
        expect(find.text(name), findsNothing);
        expect(find.byTooltip(name), findsOneWidget);
        final box = tester.getRect(find.byTooltip(name));
        expect(
          box.width,
          greaterThanOrEqualTo(DesignTokens.minTouchTarget - 4),
        );
      }
      await tester.tap(find.byTooltip('Alarms'));
      expect(picked, [1]);
    },
  );

  testWidgets('glass by default, opaque and blur-free in high contrast', (
    tester,
  ) async {
    usePhone(tester);
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();
    final glass = tester.widget<Material>(
      find.byKey(const Key('floating-nav-pill')),
    );
    expect(glass.color!.a, closeTo(DesignTokens.navGlassOpacity, 0.01));
    expect(glass.shape, isA<StadiumBorder>());
    expect(find.byType(BackdropFilter), findsOneWidget);

    await tester.pumpWidget(host(highContrast: true));
    await tester.pumpAndSettle();
    final solid = tester.widget<Material>(
      find.byKey(const Key('floating-nav-pill')),
    );
    expect(solid.color!.a, 1.0);
    expect(find.byType(BackdropFilter), findsNothing);
  });

  testWidgets('accessibility: tap targets, labels and selected state', (
    tester,
  ) async {
    usePhone(tester);
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();

    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));

    expect(
      tester.getSemantics(find.byTooltip('Home')),
      matchesSemantics(
        label: 'Home',
        isButton: true,
        isSelected: true,
        hasSelectedState: true,
        hasTapAction: true,
        hasEnabledState: true,
        isEnabled: true,
      ),
    );
    expect(find.bySemanticsLabel('Alarms, 3 active'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('text scale 2.0x does not overflow the 64dp bar', (tester) async {
    usePhone(tester);
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.platformDispatcher.clearAllTestValues);
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(
      tester.getSize(find.byKey(const Key('floating-nav-pill'))).height,
      DesignTokens.navBarHeight,
    );
  });
}
