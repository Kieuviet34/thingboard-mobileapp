import 'package:flutter_test/flutter_test.dart';
import 'package:thingsboard_democloud_app/core/api/client/tb_api_client.dart';
import 'package:thingsboard_democloud_app/core/api/repositories/customer_repository.dart';
import 'package:thingsboard_democloud_app/core/models/models.dart';

import '../../../../helpers/fake_secure_storage.dart';
import '../../../../helpers/mock_dio_adapter.dart';
import '../../../../helpers/openapi_contract.dart';

/// Contract test: every request `RestCustomerRepository` sends must exist in the
/// ThingsBoard 4.4.x OpenAPI, and every response shape must parse correctly.
void main() {
  late MockDioAdapter adapter;
  late RestCustomerRepository repo;
  final contract = OpenApiContract.load();

  // Shape: CustomerInfo (spec schema, `/api/customerInfos/all`).
  const customerInfoJson = <String, dynamic>{
    'id': {'entityType': 'CUSTOMER', 'id': 'c-1'},
    'createdTime': 1700000000000,
    'title': 'Acme',
    'name': 'Acme',
    'country': 'VN',
    'state': '',
    'city': 'Hanoi',
    'address': '1 Main St',
    'address2': '',
    'zip': '100000',
    'phone': '+84 900 000 000',
    'email': 'ops@acme.example',
    'tenantId': {'entityType': 'TENANT', 'id': 't-1'},
    'parentCustomerId': {'entityType': 'CUSTOMER', 'id': 'c-0'},
    'version': 1,
    'ownerName': 'Tenant',
    'groups': <dynamic>[],
    'additionalInfo': {},
  };

  // Shape: Customer (spec schema, `/api/customer/{id}` and `/api/customers`).
  const customerJson = <String, dynamic>{
    'id': {'entityType': 'CUSTOMER', 'id': 'c-2'},
    'createdTime': 1700000000100,
    'title': 'Globex',
    'country': 'US',
    'state': 'CA',
    'city': 'Austin',
    'address': '2 Side St',
    'address2': '',
    'zip': '73301',
    'phone': '',
    'email': 'hq@globex.example',
    'tenantId': {'entityType': 'TENANT', 'id': 't-1'},
    'version': 1,
    'additionalInfo': {},
  };

  Map<String, dynamic> page(List<Map<String, dynamic>> items) => {
    'data': items,
    'totalPages': 1,
    'totalElements': items.length,
    'hasNext': false,
  };

  setUp(() {
    adapter = MockDioAdapter();
    repo = RestCustomerRepository(
      client: TbApiClient(
        baseUrl: 'https://thingsboard.democloud.xyz/',
        storage: FakeSecureStorage(),
        httpClientAdapter: adapter,
      ),
    );
  });

  test(
    'getCustomers sends spec-valid query and parses CustomerInfo page',
    () async {
      adapter.on(
        'GET',
        '/api/customerInfos/all',
        (_) => MockDioAdapter.jsonResponse(page([customerInfoJson])),
      );

      final result = await repo.getCustomers(
        const PageQuery(textSearch: ' acme '),
      );

      contract.expectAllConform(adapter);
      expect(adapter.capturedRequests.single.queryParameters, {
        'page': 0,
        'pageSize': 20,
        'textSearch': 'acme',
        'sortProperty': 'createdTime',
        'sortOrder': 'DESC',
        'includeCustomers': true,
      });
      final customer = result.data.single;
      expect(customer.id, 'c-1');
      expect(customer.title, 'Acme');
      expect(customer.country, 'VN');
      expect(customer.city, 'Hanoi');
      expect(customer.email, 'ops@acme.example');
      expect(customer.parentCustomerId, 'c-0');
      expect(customer.createdTime, 1700000000000);
      expect(customer.locationSummary, 'Hanoi, VN');
      expect(result.totalElements, 1);
      expect(result.hasNext, isFalse);
      expect(
        contract.coveredOperations(adapter.capturedRequests),
        contains('GET /api/customerInfos/all'),
      );
    },
  );

  test('getCustomers falls back to /api/customers only on HTTP 404', () async {
    adapter
      ..enqueue(
        'GET',
        '/api/customerInfos/all',
        (_) => MockDioAdapter.jsonResponse({'status': 404}, statusCode: 404),
      )
      ..on(
        'GET',
        '/api/customers',
        (_) => MockDioAdapter.jsonResponse(page([customerJson])),
      );

    final result = await repo.getCustomers(const PageQuery());

    contract.expectAllConform(adapter);
    expect(adapter.capturedRequests.map((r) => r.path).toList(), [
      '/api/customerInfos/all',
      '/api/customers',
    ]);
    expect(adapter.capturedRequests.last.queryParameters, {
      'page': 0,
      'pageSize': 20,
      'sortProperty': 'createdTime',
      'sortOrder': 'DESC',
    });
    final customer = result.data.single;
    expect(customer.id, 'c-2');
    expect(customer.title, 'Globex');
    expect(customer.locationSummary, 'Austin, CA, US');
    expect(
      contract.coveredOperations(adapter.capturedRequests),
      containsAll(<String>['GET /api/customerInfos/all', 'GET /api/customers']),
    );
  });

  test(
    'getCustomers rethrows HTTP 403 without the /api/customers fallback',
    () async {
      adapter.on(
        'GET',
        '/api/customerInfos/all',
        (_) => MockDioAdapter.jsonResponse({'status': 403}, statusCode: 403),
      );

      await expectLater(
        repo.getCustomers(const PageQuery()),
        throwsA(
          isA<TbFailure>().having(
            (f) => f.type,
            'type',
            TbFailureType.permissionDenied,
          ),
        ),
      );

      contract.expectAllConform(adapter);
      expect(
        adapter.capturedRequests.map((r) => r.path),
        isNot(contains('/api/customers')),
      );
    },
  );

  test('getCustomerInfo uses /api/customer/info/{customerId}', () async {
    adapter.on(
      'GET',
      '/api/customer/info/c-1',
      (_) => MockDioAdapter.jsonResponse(customerInfoJson),
    );

    final customer = await repo.getCustomerInfo('c-1');

    contract.expectAllConform(adapter);
    expect(adapter.capturedRequests.single.path, '/api/customer/info/c-1');
    expect(customer.id, 'c-1');
    expect(customer.title, 'Acme');
    expect(customer.address, '1 Main St');
    expect(customer.parentCustomerId, 'c-0');
    expect(
      contract.coveredOperations(adapter.capturedRequests),
      contains('GET /api/customer/info/{customerId}'),
    );
  });

  test(
    'getCustomerInfo falls back to /api/customer/{customerId} only on HTTP 404',
    () async {
      adapter
        ..enqueue(
          'GET',
          '/api/customer/info/c-2',
          (_) => MockDioAdapter.jsonResponse({'status': 404}, statusCode: 404),
        )
        ..on(
          'GET',
          '/api/customer/c-2',
          (_) => MockDioAdapter.jsonResponse(customerJson),
        );

      final customer = await repo.getCustomerInfo('c-2');

      contract.expectAllConform(adapter);
      expect(adapter.capturedRequests.map((r) => r.path).toList(), [
        '/api/customer/info/c-2',
        '/api/customer/c-2',
      ]);
      expect(customer.id, 'c-2');
      expect(customer.title, 'Globex');
      expect(customer.parentCustomerId, isNull);
      expect(
        contract.coveredOperations(adapter.capturedRequests),
        containsAll(<String>[
          'GET /api/customer/info/{customerId}',
          'GET /api/customer/{customerId}',
        ]),
      );
    },
  );
}
