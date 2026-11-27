import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thingsboard_democloud_app/config/themes/design_tokens.dart';
import 'package:thingsboard_democloud_app/config/themes/tb_theme.dart';
import 'package:thingsboard_democloud_app/widgets/tb_list_row.dart';
import 'package:thingsboard_democloud_app/widgets/tb_section_card.dart';

void main() {
  Widget host(Widget child) => MaterialApp(
    theme: tbLightTheme(),
    home: Scaffold(body: child),
  );

  testWidgets('TbListRow shows title and one meta line', (tester) async {
    await tester.pumpWidget(
      host(const TbListRow(title: 'Boiler 1', meta: 'Thermostat · Floor 2')),
    );
    expect(find.text('Boiler 1'), findsOneWidget);
    expect(find.text('Thermostat · Floor 2'), findsOneWidget);
  });

  testWidgets('TbListRow hides empty meta and keeps 48dp minimum height', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(const TbListRow(title: 'Only title', meta: '   ')),
    );
    expect(find.text('Only title'), findsOneWidget);
    expect(
      tester.getSize(find.byType(TbListRow)).height,
      greaterThanOrEqualTo(DesignTokens.minTouchTarget),
    );
  });

  testWidgets('TbListRow fires onTap when tapped', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      host(TbListRow(title: 'Tap me', onTap: () => taps++)),
    );
    await tester.tap(find.text('Tap me'));
    expect(taps, 1);
  });

  testWidgets(
    'TbListRow applies 16dp horizontal padding standalone and avoids double padding inside TbSectionCard',
    (tester) async {
      await tester.pumpWidget(
        host(
          const Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TbListRow(title: 'Standalone row'),
              TbSectionCard(
                title: 'Section Header',
                child: TbListRow(title: 'Card row'),
              ),
            ],
          ),
        ),
      );

      final standaloneLeft = tester.getTopLeft(find.text('Standalone row')).dx;
      final sectionHeaderLeft = tester
          .getTopLeft(find.text('Section Header'))
          .dx;
      final cardRowLeft = tester.getTopLeft(find.text('Card row')).dx;

      expect(standaloneLeft, DesignTokens.spacing16);
      expect(cardRowLeft, sectionHeaderLeft);
      expect(cardRowLeft, DesignTokens.spacing16);
    },
  );
}
