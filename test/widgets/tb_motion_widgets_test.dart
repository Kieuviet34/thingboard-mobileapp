import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:thingsboard_democloud_app/config/themes/tb_theme.dart';
import 'package:thingsboard_democloud_app/core/models/alarm_models.dart';
import 'package:thingsboard_democloud_app/widgets/icons/tb_icons.dart';
import 'package:thingsboard_democloud_app/widgets/tb_app_bar.dart';
import 'package:thingsboard_democloud_app/widgets/tb_app_search_bar.dart';
import 'package:thingsboard_democloud_app/widgets/tb_empty_state.dart';
import 'package:thingsboard_democloud_app/widgets/tb_metric_pill.dart';
import 'package:thingsboard_democloud_app/widgets/tb_motion.dart';
import 'package:thingsboard_democloud_app/widgets/tb_shimmer.dart';
import 'package:thingsboard_democloud_app/widgets/tb_status_badge.dart';

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  group('Minimal-text IoT widgets & GPU-safe motion', () {
    testWidgets('TbStatusBadge renders icon + label without color-only state', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: tbLightTheme(),
          home: Scaffold(
            body: Column(
              children: [
                TbStatusBadge.severity(AlarmSeverity.critical),
                TbStatusBadge.online(true),
                TbStatusBadge.online(false),
                TbStatusBadge.demo(),
              ],
            ),
          ),
        ),
      );

      expect(find.text('CRITICAL'), findsOneWidget);
      expect(find.text('ONLINE'), findsOneWidget);
      expect(find.text('OFFLINE'), findsOneWidget);
      expect(find.text('DEMO'), findsOneWidget);
      expect(find.byType(TbIcon), findsNWidgets(4));
    });

    testWidgets(
      'TbMetricPill uses tabular figures and survives 2.0x text scale',
      (WidgetTester tester) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: tbLightTheme(),
            home: const MediaQuery(
              data: MediaQueryData(textScaler: TextScaler.linear(2.0)),
              child: Scaffold(
                body: SizedBox(
                  width: 240,
                  child: TbMetricPill(
                    icon: TbIconKind.temperature,
                    value: '24.6',
                    unit: '°C',
                    label: 'Temp',
                  ),
                ),
              ),
            ),
          ),
        );

        expect(find.text('24.6 °C'), findsOneWidget);
        expect(find.text('Temp'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('TbEmptyState keeps minimal title + >=48dp action button', (
      WidgetTester tester,
    ) async {
      var tapped = false;
      await tester.pumpWidget(
        MaterialApp(
          theme: tbDarkTheme(),
          home: Scaffold(
            body: TbEmptyState(
              icon: TbIconKind.sensorNode,
              title: 'No devices',
              actionLabel: 'Retry',
              onAction: () => tapped = true,
            ),
          ),
        ),
      );

      expect(find.text('No devices'), findsOneWidget);
      final button = find.widgetWithText(FilledButton, 'Retry');
      expect(button, findsOneWidget);
      final size = tester.getSize(button);
      expect(size.height, greaterThanOrEqualTo(48.0));

      await tester.tap(button);
      expect(tapped, isTrue);
    });

    testWidgets('Reduced motion (disableAnimations: true) settles cleanly', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: tbLightTheme(),
          home: const MediaQuery(
            data: MediaQueryData(disableAnimations: true),
            child: Scaffold(
              body: Column(
                children: [
                  TbShimmerList(itemCount: 2),
                  TbStaggeredEntry(index: 1, child: Text('Staggered')),
                  LivePulseDot(active: true),
                  TbSparklineChart(
                    values: [10, 14, 12, 18, 16],
                    semanticLabel: 'Temperature trend',
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(find.text('Staggered'), findsOneWidget);
      expect(find.bySemanticsLabel('Temperature trend'), findsOneWidget);
    });

    testWidgets('TbPressScale and animated TbShimmer dispose cleanly', (
      WidgetTester tester,
    ) async {
      var pressed = false;
      await tester.pumpWidget(
        MaterialApp(
          theme: tbLightTheme(),
          home: Scaffold(
            body: Column(
              children: [
                TbPressScale(
                  onTap: () => pressed = true,
                  child: const SizedBox(
                    width: 120,
                    height: 48,
                    child: Center(child: Text('Tap me')),
                  ),
                ),
                const TbShimmer(width: 100, height: 16),
              ],
            ),
          ),
        ),
      );

      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.text('Tap me'));
      await tester.pump(const Duration(milliseconds: 200));
      expect(pressed, isTrue);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'TbAppBar and debounced TbAppSearchBar meet >=48dp target and debounce 300ms',
      (WidgetTester tester) async {
        final queries = <String>[];
        await tester.pumpWidget(
          MaterialApp(
            theme: tbLightTheme(),
            home: Scaffold(
              appBar: TbAppSearchBar(
                searchHint: 'Search devices',
                onSearch: queries.add,
                leading: IconButton(
                  tooltip: 'Back',
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () {},
                ),
              ),
              body: const SizedBox(),
            ),
          ),
        );

        final backButton = find.byType(IconButton).first;
        expect(tester.getSize(backButton).width, greaterThanOrEqualTo(48.0));
        expect(tester.getSize(backButton).height, greaterThanOrEqualTo(48.0));

        await tester.enterText(find.byType(TextField), 'sensor');
        expect(queries, isEmpty);

        await tester.pump(const Duration(milliseconds: 310));
        expect(queries, ['sensor']);

        final clearBtn = find.byTooltip('Clear search');
        expect(clearBtn, findsOneWidget);
        expect(tester.getSize(clearBtn).width, greaterThanOrEqualTo(48.0));
        expect(tester.getSize(clearBtn).height, greaterThanOrEqualTo(48.0));
        await tester.tap(clearBtn);
        await tester.pump();
        expect(queries.last, '');

        await tester.pumpWidget(
          MaterialApp(
            theme: tbLightTheme(),
            home: Scaffold(
              appBar: TbAppBar(
                title: const Text('Devices'),
                showLoadingIndicator: true,
              ),
              body: const SizedBox(),
            ),
          ),
        );
        expect(find.text('Devices'), findsOneWidget);
        expect(find.byType(LinearProgressIndicator), findsOneWidget);
      },
    );
  });
}
