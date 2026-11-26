import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thingsboard_democloud_app/config/themes/design_tokens.dart';
import 'package:thingsboard_democloud_app/config/themes/tb_theme.dart';
import 'package:thingsboard_democloud_app/widgets/tb_list_row.dart';

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
}
