import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thingsboard_democloud_app/config/themes/tb_theme.dart';
import 'package:thingsboard_democloud_app/widgets/tb_section_card.dart';

Widget _host(Widget child, {ThemeData? theme}) => MaterialApp(
  theme: theme ?? tbLightTheme(),
  home: Scaffold(
    body: Padding(padding: const EdgeInsets.all(16), child: child),
  ),
);

BoxDecoration _cardDecoration(WidgetTester tester) => tester
    .widgetList<DecoratedBox>(find.byType(DecoratedBox))
    .map((w) => w.decoration)
    .whereType<BoxDecoration>()
    .firstWhere((d) => d.border != null);

void main() {
  testWidgets('TbSectionCard renders title, child and trailing action', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        TbSectionCard(
          title: 'Overview',
          trailing: IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: () {},
          ),
          child: const Text('Body text'),
        ),
      ),
    );

    expect(find.text('Overview'), findsOneWidget);
    expect(find.text('Body text'), findsOneWidget);
    expect(find.byTooltip('Refresh'), findsOneWidget);
  });

  testWidgets(
    'TbSectionCard uses surfaceContainerLow with outlineVariant border',
    (tester) async {
      final theme = tbLightTheme();
      await tester.pumpWidget(
        _host(
          const TbSectionCard(title: 'T', child: SizedBox()),
          theme: theme,
        ),
      );

      final decoration = _cardDecoration(tester);
      expect(decoration.color, theme.colorScheme.surfaceContainerLow);
      expect(
        (decoration.border! as Border).top.color,
        theme.colorScheme.outlineVariant,
      );
    },
  );

  testWidgets('TbSectionCard uses dark scheme colors in dark theme', (
    tester,
  ) async {
    final theme = tbDarkTheme();
    await tester.pumpWidget(
      _host(
        const TbSectionCard(title: 'T', child: SizedBox()),
        theme: theme,
      ),
    );

    final decoration = _cardDecoration(tester);
    expect(decoration.color, theme.colorScheme.surfaceContainerLow);
    expect(
      (decoration.border! as Border).top.color,
      theme.colorScheme.outlineVariant,
    );
  });

  testWidgets('TbKvRow shows label and value, and an em dash for empty value', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        const Column(
          children: [
            TbKvRow(label: 'Profile', value: 'Thermostat'),
            TbKvRow(label: 'Owner', value: '   '),
          ],
        ),
      ),
    );

    expect(find.text('Profile'), findsOneWidget);
    expect(find.text('Thermostat'), findsOneWidget);
    expect(find.text('—'), findsOneWidget);
  });

  testWidgets('TbKvRow ellipsizes long values on a single line', (
    tester,
  ) async {
    const long =
        'a-very-long-device-profile-name-that-should-not-wrap-onto-two-lines-at-all';
    await tester.pumpWidget(
      _host(
        const SizedBox(
          width: 200,
          child: TbKvRow(label: 'Profile', value: long),
        ),
      ),
    );

    final valueText = tester.widget<Text>(find.text(long));
    expect(valueText.maxLines, 1);
    expect(valueText.overflow, TextOverflow.ellipsis);
  });
}
