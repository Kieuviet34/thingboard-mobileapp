import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:thingsboard_democloud_app/config/themes/app_colors.dart';
import 'package:thingsboard_democloud_app/config/themes/design_tokens.dart';
import 'package:thingsboard_democloud_app/config/themes/tb_status_colors.dart';
import 'package:thingsboard_democloud_app/config/themes/tb_text_styles.dart';
import 'package:thingsboard_democloud_app/config/themes/tb_theme.dart';
import 'package:thingsboard_democloud_app/config/themes/tb_theme_utils.dart';

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  group('M3 Light & Dark Themes and Status Extension', () {
    test(
      'tbLightTheme and tbDarkTheme enable Material 3 with distinct schemes',
      () {
        final light = tbLightTheme();
        final dark = tbDarkTheme();

        expect(light.useMaterial3, isTrue);
        expect(dark.useMaterial3, isTrue);
        expect(light.colorScheme.brightness, Brightness.light);
        expect(dark.colorScheme.brightness, Brightness.dark);
        expect(
          light.colorScheme.surface,
          isNot(equals(dark.colorScheme.surface)),
        );
        expect(
          light.colorScheme.onSurface,
          isNot(equals(dark.colorScheme.onSurface)),
        );
        expect(light.colorScheme.primary, AppColors.primaryBlue);
      },
    );

    test(
      'TbStatusColors ThemeExtension is attached and supports light/dark/lerp',
      () {
        final lightExt = tbLightTheme().extension<TbStatusColors>();
        final darkExt = tbDarkTheme().extension<TbStatusColors>();

        expect(lightExt, isNotNull);
        expect(darkExt, isNotNull);
        expect(lightExt!.critical, isNot(equals(darkExt!.critical)));
        expect(lightExt.online, isNot(equals(lightExt.offline)));
        expect(lightExt.demo, isNot(equals(lightExt.cleared)));

        final mid = lightExt.lerp(darkExt, 0.5);
        expect(mid, isA<TbStatusColors>());
        final copied = lightExt.copyWith(critical: Colors.pink);
        expect(copied.critical, Colors.pink);
      },
    );

    test(
      'TbThemeUtils exposes light, dark, and defaultTheme with M3 enabled',
      () {
        expect(TbThemeUtils.lightTheme.useMaterial3, isTrue);
        expect(TbThemeUtils.darkTheme.useMaterial3, isTrue);
        expect(TbThemeUtils.defaultTheme.useMaterial3, isTrue);
        expect(TbThemeUtils.darkTheme.brightness, Brightness.dark);
      },
    );

    test('DesignTokens and TbTextStyles expose M3 and tabular helpers', () {
      expect(DesignTokens.paddingZero, EdgeInsets.zero);
      expect(DesignTokens.minTouchTarget, 48.0);
      expect(DesignTokens.compactMaxWidth, 600.0);
      expect(DesignTokens.mediumMaxWidth, 840.0);

      final tabular = TbTextStyles.tabular(TbTextStyles.titleMedium);
      expect(
        tabular.fontFeatures,
        contains(const FontFeature.tabularFigures()),
      );
    });

    test(
      'themeModeProvider defaults to ThemeMode.system and updates cleanly',
      () {
        final container = ProviderContainer();
        addTearDown(container.dispose);

        expect(container.read(themeModeProvider), ThemeMode.system);
        container.read(themeModeProvider.notifier).setThemeMode(ThemeMode.dark);
        expect(container.read(themeModeProvider), ThemeMode.dark);
        container
            .read(themeModeProvider.notifier)
            .setThemeMode(ThemeMode.light);
        expect(container.read(themeModeProvider), ThemeMode.light);
      },
    );

    testWidgets('TbStatusColors.of resolves from BuildContext in both modes', (
      WidgetTester tester,
    ) async {
      late TbStatusColors resolvedLight;
      late TbStatusColors resolvedDark;

      await tester.pumpWidget(
        MaterialApp(
          theme: tbLightTheme(),
          home: Builder(
            builder: (context) {
              resolvedLight = TbStatusColors.of(context);
              return const SizedBox();
            },
          ),
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: tbDarkTheme(),
          home: Builder(
            builder: (context) {
              resolvedDark = TbStatusColors.of(context);
              return const SizedBox();
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        resolvedLight.criticalContainer,
        isNot(equals(resolvedDark.criticalContainer)),
      );
      expect(
        resolvedLight.onlineContainer,
        isNot(equals(resolvedDark.onlineContainer)),
      );
    });
  });
}
