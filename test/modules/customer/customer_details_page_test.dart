import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:thingsboard_democloud_app/config/themes/tb_theme.dart';
import 'package:thingsboard_democloud_app/core/api/controllers/customer_controller.dart';
import 'package:thingsboard_democloud_app/core/api/controllers/server_config_controller.dart';
import 'package:thingsboard_democloud_app/core/models/customer_models.dart';
import 'package:thingsboard_democloud_app/core/models/tb_failure.dart';
import 'package:thingsboard_democloud_app/modules/customer/customer_details_page.dart';
import 'package:thingsboard_democloud_app/widgets/tb_empty_state.dart';
import 'package:thingsboard_democloud_app/widgets/tb_section_card.dart';

import '../../helpers/fake_app_preferences.dart';
import '../../helpers/fake_secure_storage.dart';
import '../../helpers/fake_ws_channel.dart';
import '../../helpers/mock_dio_adapter.dart';

const _mockCustomer = TbCustomerInfo(
  id: 'cust-1',
  title: 'Global Energy Corp',
  email: 'contact@globalenergy.com',
  phone: '+1 555-0199',
  country: 'United States',
  state: 'CA',
  city: 'San Francisco',
  address: '100 Market St',
  address2: 'Suite 400',
  zip: '94105',
  createdTime: 1700000000000,
);

void main() {
  Widget buildApp({
    required List<Override> overrides,
    String customerId = 'cust-1',
    bool embedded = false,
    Future<bool> Function(Uri)? onLaunchUrl,
    ThemeData? theme,
    double textScale = 1.0,
    bool disableAnimations = false,
  }) {
    return ProviderScope(
      overrides: [
        tbStorageProvider.overrideWithValue(FakeSecureStorage()),
        tbAppPreferencesProvider.overrideWithValue(FakeAppPreferences()),
        tbHttpClientAdapterProvider.overrideWithValue(MockDioAdapter()),
        wsChannelFactoryProvider.overrideWithValue(
          (_) => FakeWebSocketChannel(),
        ),
        ...overrides,
      ],
      child: MediaQuery(
        data: MediaQueryData(
          size: const Size(390, 844),
          textScaler: TextScaler.linear(textScale),
          disableAnimations: disableAnimations,
        ),
        child: MaterialApp(
          theme: theme ?? tbLightTheme(),
          home: CustomerDetailsPage(
            customerId: customerId,
            embedded: embedded,
            onLaunchUrl: onLaunchUrl,
          ),
        ),
      ),
    );
  }

  group('CustomerDetailsPage', () {
    testWidgets('uses Contact and Details TbSectionCard sections', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildApp(
          overrides: [
            customerDetailsProvider(
              'cust-1',
            ).overrideWith((ref) => Future.value(_mockCustomer)),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.widgetWithText(TbSectionCard, 'Contact'), findsOneWidget);
      expect(find.widgetWithText(TbSectionCard, 'Details'), findsOneWidget);
      expect(find.widgetWithText(TbKvRow, 'Location'), findsOneWidget);
      expect(find.widgetWithText(TbKvRow, 'Address'), findsOneWidget);
      expect(find.widgetWithText(TbKvRow, 'ZIP'), findsOneWidget);
    });

    testWidgets('omits Contact section when no email or phone', (tester) async {
      await tester.pumpWidget(
        buildApp(
          overrides: [
            customerDetailsProvider('cust-1').overrideWith(
              (ref) => Future.value(
                const TbCustomerInfo(id: 'cust-1', title: 'Bare Co'),
              ),
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Contact'), findsNothing);
      expect(find.widgetWithText(TbSectionCard, 'Details'), findsOneWidget);
    });

    testWidgets('renders customer details, contact info and address cards', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildApp(
          overrides: [
            customerDetailsProvider(
              'cust-1',
            ).overrideWith((ref) => Future.value(_mockCustomer)),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Global Energy Corp'), findsWidgets);
      expect(find.text('contact@globalenergy.com'), findsOneWidget);
      expect(find.text('+1 555-0199'), findsOneWidget);
      expect(find.text('San Francisco, CA, United States'), findsOneWidget);
      expect(find.text('100 Market St'), findsOneWidget);
      expect(find.text('Suite 400'), findsOneWidget);
      expect(find.text('94105'), findsOneWidget);
    });

    testWidgets('tap on email and phone triggers onLaunchUrl callback', (
      tester,
    ) async {
      final launched = <String>[];
      await tester.pumpWidget(
        buildApp(
          overrides: [
            customerDetailsProvider(
              'cust-1',
            ).overrideWith((ref) => Future.value(_mockCustomer)),
          ],
          onLaunchUrl: (uri) async {
            launched.add(uri.toString());
            return true;
          },
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.widgetWithText(InkWell, 'contact@globalenergy.com'),
      );
      await tester.pumpAndSettle();
      expect(launched, contains('mailto:contact@globalenergy.com'));

      await tester.tap(find.widgetWithText(InkWell, '+1 555-0199'));
      await tester.pumpAndSettle();
      expect(launched, contains('tel:+1%20555-0199'));
    });

    testWidgets('renders 403 permissionDenied message without retry button', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildApp(
          overrides: [
            customerDetailsProvider('cust-1').overrideWith(
              (ref) => Future.error(
                const TbFailure(
                  type: TbFailureType.permissionDenied,
                  message: 'Forbidden',
                ),
              ),
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Access Restricted'), findsOneWidget);
      expect(find.byType(TbEmptyState), findsOneWidget);
      expect(find.text('Retry'), findsNothing);
    });

    testWidgets('embedded mode renders without top AppBar', (tester) async {
      await tester.pumpWidget(
        buildApp(
          customerId: 'cust-1',
          embedded: true,
          overrides: [
            customerDetailsProvider(
              'cust-1',
            ).overrideWith((ref) => Future.value(_mockCustomer)),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(AppBar), findsNothing);
      expect(find.text('Global Energy Corp'), findsOneWidget);
    });

    testWidgets('renders cleanly in Dark mode at 2.0x text scale', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildApp(
          theme: tbDarkTheme(),
          textScale: 2.0,
          disableAnimations: true,
          overrides: [
            customerDetailsProvider(
              'cust-1',
            ).overrideWith((ref) => Future.value(_mockCustomer)),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Global Energy Corp'), findsWidgets);
    });
  });
}
