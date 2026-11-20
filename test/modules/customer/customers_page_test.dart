import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:thingsboard_democloud_app/config/themes/tb_theme.dart';
import 'package:thingsboard_democloud_app/core/api/controllers/customer_controller.dart';
import 'package:thingsboard_democloud_app/core/api/controllers/server_config_controller.dart';
import 'package:thingsboard_democloud_app/core/api/repositories/customer_repository.dart';
import 'package:thingsboard_democloud_app/core/models/customer_models.dart';
import 'package:thingsboard_democloud_app/core/models/pagination.dart';
import 'package:thingsboard_democloud_app/core/models/tb_failure.dart';
import 'package:thingsboard_democloud_app/modules/customer/customer_details_page.dart';
import 'package:thingsboard_democloud_app/modules/customer/customers_page.dart';
import 'package:thingsboard_democloud_app/widgets/icons/tb_icons.dart';
import 'package:thingsboard_democloud_app/widgets/tb_empty_state.dart';

import '../../helpers/fake_app_preferences.dart';
import '../../helpers/fake_secure_storage.dart';
import '../../helpers/fake_ws_channel.dart';
import '../../helpers/mock_dio_adapter.dart';

class _FakeCustomerRepo implements CustomerRepository {
  _FakeCustomerRepo({this.customers = const [], this.throwFailure});

  List<TbCustomerInfo> customers;
  TbFailure? throwFailure;
  int getCustomersCalls = 0;

  @override
  Future<PageData<TbCustomerInfo>> getCustomers(
    PageQuery query, {
    CancelToken? cancelToken,
  }) async {
    getCustomersCalls++;
    if (throwFailure != null) throw throwFailure!;

    final search = query.textSearch?.toLowerCase() ?? '';
    final filtered = customers.where((c) {
      if (search.isEmpty) return true;
      return c.title.toLowerCase().contains(search) ||
          c.city.toLowerCase().contains(search);
    }).toList();

    return PageData<TbCustomerInfo>(
      data: filtered,
      totalPages: 1,
      totalElements: filtered.length,
      hasNext: false,
    );
  }

  @override
  Future<TbCustomerInfo> getCustomerInfo(String customerId) async {
    return customers.firstWhere(
      (c) => c.id == customerId,
      orElse: () =>
          TbCustomerInfo(id: customerId, title: 'Customer $customerId'),
    );
  }
}

final _sampleCustomers = [
  const TbCustomerInfo(
    id: 'c-1',
    title: 'Acme Renewables',
    city: 'Berlin',
    country: 'Germany',
    email: 'info@acme.de',
  ),
  const TbCustomerInfo(
    id: 'c-2',
    title: 'Blue River Logistics',
    city: 'Rotterdam',
    country: 'Netherlands',
    phone: '+31 10 123456',
  ),
];

void main() {
  Widget buildApp({
    required CustomerRepository repo,
    Size size = const Size(390, 844),
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
        customerRepositoryProvider.overrideWithValue(repo),
      ],
      child: MediaQuery(
        data: MediaQueryData(
          size: size,
          textScaler: TextScaler.linear(textScale),
          disableAnimations: disableAnimations,
        ),
        child: MaterialApp(
          theme: theme ?? tbLightTheme(),
          home: const CustomersPage(),
        ),
      ),
    );
  }

  group('CustomersPage', () {
    testWidgets('renders list of customers with TbIcon and location', (
      tester,
    ) async {
      final repo = _FakeCustomerRepo(customers: _sampleCustomers);
      await tester.pumpWidget(buildApp(repo: repo));
      await tester.pumpAndSettle();

      expect(find.text('Customers'), findsOneWidget);
      expect(find.text('Acme Renewables'), findsOneWidget);
      expect(find.text('Blue River Logistics'), findsOneWidget);
      expect(find.text('Berlin, Germany'), findsOneWidget);
      expect(find.byType(TbIcon), findsWidgets);
    });

    testWidgets('search bar filters customer list', (tester) async {
      final repo = _FakeCustomerRepo(customers: _sampleCustomers);
      await tester.pumpWidget(buildApp(repo: repo));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Search customers'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'Acme');
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();

      expect(find.text('Acme Renewables'), findsOneWidget);
      expect(find.text('Blue River Logistics'), findsNothing);
    });

    testWidgets('empty customer list renders TbEmptyState', (tester) async {
      final repo = _FakeCustomerRepo(customers: []);
      await tester.pumpWidget(buildApp(repo: repo));
      await tester.pumpAndSettle();

      expect(find.byType(TbEmptyState), findsOneWidget);
      expect(find.text('No customers available'), findsOneWidget);
    });

    testWidgets('403 permissionDenied renders Access Restricted empty state', (
      tester,
    ) async {
      final repo = _FakeCustomerRepo(
        throwFailure: const TbFailure(
          type: TbFailureType.permissionDenied,
          message: 'Forbidden',
        ),
      );
      await tester.pumpWidget(buildApp(repo: repo));
      await tester.pumpAndSettle();

      expect(find.byType(TbEmptyState), findsOneWidget);
      expect(find.text('Access Restricted'), findsOneWidget);
    });

    testWidgets(
      'adaptive 2-pane master-detail renders list and details side by side on >=840dp',
      (tester) async {
        final repo = _FakeCustomerRepo(customers: _sampleCustomers);
        await tester.pumpWidget(
          buildApp(repo: repo, size: const Size(1024, 768)),
        );
        await tester.pumpAndSettle();

        expect(find.byType(VerticalDivider), findsOneWidget);
        expect(find.byType(CustomerDetailsPage), findsOneWidget);
        expect(find.text('Acme Renewables'), findsWidgets);
      },
    );

    testWidgets('renders in Dark theme at 2.0x text scale without overflow', (
      tester,
    ) async {
      final repo = _FakeCustomerRepo(customers: _sampleCustomers);
      await tester.pumpWidget(
        buildApp(
          repo: repo,
          theme: tbDarkTheme(),
          textScale: 2.0,
          disableAnimations: true,
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Customers'), findsOneWidget);
      expect(find.text('Acme Renewables'), findsOneWidget);
    });
  });
}
