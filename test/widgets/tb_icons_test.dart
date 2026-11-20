import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:thingsboard_democloud_app/config/themes/tb_theme.dart';
import 'package:thingsboard_democloud_app/core/models/alarm_models.dart';
import 'package:thingsboard_democloud_app/widgets/icons/tb_icons.dart';

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  group('TbIcons custom icon identity', () {
    testWidgets(
      'renders all TbIconKind values in light and dark themes with RepaintBoundary',
      (WidgetTester tester) async {
        for (final theme in [tbLightTheme(), tbDarkTheme()]) {
          await tester.pumpWidget(
            MaterialApp(
              theme: theme,
              home: Scaffold(
                body: SingleChildScrollView(
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final kind in TbIconKind.values)
                        TbIcon(
                          kind,
                          filled: kind.name.startsWith('nav'),
                          semanticLabel: kind.name,
                        ),
                    ],
                  ),
                ),
              ),
            ),
          );

          expect(find.byType(TbIcon), findsNWidgets(TbIconKind.values.length));
          expect(
            find.descendant(
              of: find.byType(TbIcon),
              matching: find.byType(RepaintBoundary),
            ),
            findsNWidgets(TbIconKind.values.length),
          );
          expect(
            find.descendant(
              of: find.byType(TbIcon),
              matching: find.byType(CustomPaint),
            ),
            findsNWidgets(TbIconKind.values.length),
          );
        }
      },
    );

    testWidgets('severityFor maps every AlarmSeverity to distinct icon kinds', (
      WidgetTester tester,
    ) async {
      final kinds = AlarmSeverity.values.map(TbIcons.kindForSeverity).toSet();
      expect(kinds.length, AlarmSeverity.values.length);

      await tester.pumpWidget(
        MaterialApp(
          theme: tbLightTheme(),
          home: Scaffold(
            body: Row(
              children: [
                for (final severity in AlarmSeverity.values)
                  TbIcons.severity(severity, semanticLabel: severity.label),
              ],
            ),
          ),
        ),
      );

      for (final severity in AlarmSeverity.values) {
        expect(find.bySemanticsLabel(severity.label), findsOneWidget);
      }
    });

    testWidgets(
      'respects IconTheme color inheritance and decorative ExcludeSemantics',
      (WidgetTester tester) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: tbLightTheme(),
            home: const Scaffold(
              body: IconTheme(
                data: IconThemeData(color: Colors.amber, size: 28),
                child: TbIcon(TbIconKind.sensorNode),
              ),
            ),
          ),
        );

        final customPaint = tester.widget<CustomPaint>(
          find.descendant(
            of: find.byType(TbIcon),
            matching: find.byType(CustomPaint),
          ),
        );
        expect(customPaint.size, const Size(24, 24));
        final painter = customPaint.painter! as TbIconPainter;
        expect(painter.color, Colors.amber);
        expect(
          find.descendant(
            of: find.byType(TbIcon),
            matching: find.byType(ExcludeSemantics),
          ),
          findsOneWidget,
        );
      },
    );
  });
}
