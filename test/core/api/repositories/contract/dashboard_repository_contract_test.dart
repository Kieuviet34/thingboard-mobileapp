import 'package:flutter_test/flutter_test.dart';
import 'package:thingsboard_democloud_app/core/api/client/tb_api_client.dart';
import 'package:thingsboard_democloud_app/core/api/repositories/dashboard_repository.dart';
import 'package:thingsboard_democloud_app/core/models/models.dart';

import '../../../../helpers/fake_secure_storage.dart';
import '../../../../helpers/mock_dio_adapter.dart';
import '../../../../helpers/openapi_contract.dart';

/// Contract test: every request `RestDashboardRepository` sends must exist in the
/// ThingsBoard 4.4.x OpenAPI, and every response shape must parse correctly.
void main() {
  late MockDioAdapter adapter;
  late RestDashboardRepository repo;
  final contract = OpenApiContract.load();

  const dashboardJson = <String, dynamic>{
    'id': {'entityType': 'DASHBOARD', 'id': 'dash-1'},
    'createdTime': 1700000000000,
    'title': 'Factory Overview',
    'mobileHide': false,
    'mobileOrder': 2,
    'assignedCustomers': [
      {
        'customerId': {'entityType': 'CUSTOMER', 'id': 'c-1'},
        'title': 'Acme',
        'public': false,
      },
      {
        'customerId': {'entityType': 'CUSTOMER', 'id': 'c-2'},
        'title': '',
        'public': false,
      },
    ],
  };

  Map<String, dynamic> page(List<Map<String, dynamic>> items) => {
    'data': items,
    'totalPages': 1,
    'totalElements': items.length,
    'hasNext': false,
  };

  setUp(() {
    adapter = MockDioAdapter();
    repo = RestDashboardRepository(
      client: TbApiClient(
        baseUrl: 'https://thingsboard.democloud.xyz/',
        storage: FakeSecureStorage(),
        httpClientAdapter: adapter,
      ),
    );
  });

  test(
    'getDashboards (custom query) sends spec-valid params and parses page',
    () async {
      adapter.on(
        'GET',
        '/api/user/dashboards',
        (_) => MockDioAdapter.jsonResponse(
          page([
            dashboardJson,
            {
              'id': {'entityType': 'DASHBOARD', 'id': 'dash-2'},
              'name': 'Legacy name only',
              'createdTime': 1700000000100,
            },
          ]),
        ),
      );

      final result = await repo.getDashboards(
        const PageQuery(
          textSearch: ' factory ',
          sortProperty: 'title',
          sortOrder: SortOrder.asc,
        ),
      );

      contract.expectAllConform(adapter);
      expect(adapter.capturedRequests.single.queryParameters, {
        'page': 0,
        'pageSize': 20,
        'textSearch': 'factory',
        'sortProperty': 'title',
        'sortOrder': 'ASC',
        'mobile': true,
      });
      expect(result.totalElements, 2);
      expect(result.hasNext, isFalse);

      final first = result.data.first;
      expect(first.id, 'dash-1');
      expect(first.title, 'Factory Overview');
      expect(first.mobileHide, isFalse);
      expect(first.mobileOrder, 2);
      expect(first.createdTime, 1700000000000);
      expect(first.isStarred, isFalse);
      // Empty customer titles are dropped.
      expect(first.assignedCustomers, ['Acme']);

      // `name` is used when `title` is absent.
      expect(result.data[1].id, 'dash-2');
      expect(result.data[1].title, 'Legacy name only');

      expect(
        contract.coveredOperations(adapter.capturedRequests),
        contains('GET /api/user/dashboards'),
      );
    },
  );

  test('getDashboards default query sends createdTime DESC', () async {
    adapter.on(
      'GET',
      '/api/user/dashboards',
      (_) => MockDioAdapter.jsonResponse(page([dashboardJson])),
    );

    await repo.getDashboards(const PageQuery());

    contract.expectAllConform(adapter);
    expect(adapter.capturedRequests.single.queryParameters, {
      'page': 0,
      'pageSize': 20,
      'sortProperty': 'createdTime',
      'sortOrder': 'DESC',
      'mobile': true,
    });
  });

  test(
    'getDashboards falls back to /api/tenant/dashboards on 404 only',
    () async {
      adapter
        ..enqueue(
          'GET',
          '/api/user/dashboards',
          (_) => MockDioAdapter.jsonResponse({'status': 404}, statusCode: 404),
        )
        ..on(
          'GET',
          '/api/tenant/dashboards',
          (_) => MockDioAdapter.jsonResponse(page([dashboardJson])),
        );

      final result = await repo.getDashboards(const PageQuery());

      expect(adapter.capturedRequests.map((r) => r.path), [
        '/api/user/dashboards',
        '/api/tenant/dashboards',
      ]);
      contract.expectAllConform(adapter);
      expect(result.data.single.id, 'dash-1');
      expect(
        contract.coveredOperations(adapter.capturedRequests),
        containsAll(<String>[
          'GET /api/user/dashboards',
          'GET /api/tenant/dashboards',
        ]),
      );
    },
  );

  test(
    'getDashboards for customer user falls back to /api/customer/{customerId}/dashboards',
    () async {
      adapter
        ..enqueue(
          'GET',
          '/api/user/dashboards',
          (_) => MockDioAdapter.jsonResponse({'status': 404}, statusCode: 404),
        )
        ..on(
          'GET',
          '/api/customer/c-1/dashboards',
          (_) => MockDioAdapter.jsonResponse(page([dashboardJson])),
        );

      final result = await repo.getDashboards(
        const PageQuery(),
        authority: Authority.customerUser,
        customerId: 'c-1',
      );

      expect(adapter.capturedRequests.map((r) => r.path), [
        '/api/user/dashboards',
        '/api/customer/c-1/dashboards',
      ]);
      contract.expectAllConform(adapter);
      expect(result.data.single.title, 'Factory Overview');
      expect(
        contract.coveredOperations(adapter.capturedRequests),
        contains('GET /api/customer/{customerId}/dashboards'),
      );
    },
  );

  test('getDashboards does not swallow 403 (no fallback)', () async {
    adapter.enqueue(
      'GET',
      '/api/user/dashboards',
      (_) => MockDioAdapter.jsonResponse({
        'status': 403,
        'message': 'Permission denied',
      }, statusCode: 403),
    );

    await expectLater(
      repo.getDashboards(const PageQuery()),
      throwsA(
        isA<TbFailure>().having(
          (e) => e.type,
          'type',
          TbFailureType.permissionDenied,
        ),
      ),
    );

    expect(adapter.capturedRequests, hasLength(1));
    contract.expectAllConform(adapter);
  });

  test('getHomeDashboardInfo sends GET and parses dashboardId', () async {
    adapter.on(
      'GET',
      '/api/dashboard/home/info',
      (_) => MockDioAdapter.jsonResponse({
        'dashboardId': {'entityType': 'DASHBOARD', 'id': 'dash-1'},
        'hideDashboardToolbar': false,
      }),
    );

    final home = await repo.getHomeDashboardInfo();

    contract.expectAllConform(adapter);
    expect(home?.dashboardId, 'dash-1');
    expect(home?.hideDashboardToolbar, isFalse);
    expect(
      contract.coveredOperations(adapter.capturedRequests),
      contains('GET /api/dashboard/home/info'),
    );
  });

  test('getHomeDashboardInfo returns null on 404 only', () async {
    adapter.enqueue(
      'GET',
      '/api/dashboard/home/info',
      (_) => MockDioAdapter.jsonResponse({'status': 404}, statusCode: 404),
    );

    expect(await repo.getHomeDashboardInfo(), isNull);
    contract.expectAllConform(adapter);
  });

  test('getHomeDashboardInfo rethrows 403', () async {
    adapter.enqueue(
      'GET',
      '/api/dashboard/home/info',
      (_) => MockDioAdapter.jsonResponse({
        'status': 403,
        'message': 'Permission denied',
      }, statusCode: 403),
    );

    await expectLater(
      repo.getHomeDashboardInfo(),
      throwsA(
        isA<TbFailure>().having(
          (e) => e.type,
          'type',
          TbFailureType.permissionDenied,
        ),
      ),
    );
    contract.expectAllConform(adapter);
  });

  test('getLastVisitedDashboards parses last and starred lists', () async {
    adapter.on(
      'GET',
      '/api/user/lastVisitedDashboards',
      (_) => MockDioAdapter.jsonResponse({
        'last': [
          {
            'id': 'dash-2',
            'title': 'Energy',
            'starred': false,
            'lastVisited': 1700000005000,
          },
          {
            'id': 'dash-1',
            'title': 'Factory Overview',
            'starred': true,
            'lastVisited': 1700000004000,
          },
        ],
        'starred': [
          {
            'id': 'dash-1',
            'title': 'Factory Overview',
            'starredAt': 1700000001000,
          },
        ],
      }),
    );

    final info = await repo.getLastVisitedDashboards();

    contract.expectAllConform(adapter);
    expect(info.last.map((e) => e.id), ['dash-2', 'dash-1']);
    expect(info.last.first.title, 'Energy');
    expect(info.last.first.starred, isFalse);
    expect(info.last.first.timestamp, 1700000005000);
    expect(info.starred.single.id, 'dash-1');
    expect(info.starred.single.title, 'Factory Overview');
    // Starred entries carry no `starred` flag; the app treats them as starred.
    expect(info.starred.single.starred, isTrue);
    expect(info.starred.single.timestamp, 1700000001000);
    expect(
      contract.coveredOperations(adapter.capturedRequests),
      contains('GET /api/user/lastVisitedDashboards'),
    );
  });

  test('getLastVisitedDashboards returns empty info on 404 only', () async {
    adapter.enqueue(
      'GET',
      '/api/user/lastVisitedDashboards',
      (_) => MockDioAdapter.jsonResponse({'status': 404}, statusCode: 404),
    );

    final info = await repo.getLastVisitedDashboards();

    expect(info.last, isEmpty);
    expect(info.starred, isEmpty);
    contract.expectAllConform(adapter);
  });

  test('getLastVisitedDashboards rethrows 403', () async {
    adapter.enqueue(
      'GET',
      '/api/user/lastVisitedDashboards',
      (_) => MockDioAdapter.jsonResponse({
        'status': 403,
        'message': 'Permission denied',
      }, statusCode: 403),
    );

    await expectLater(
      repo.getLastVisitedDashboards(),
      throwsA(
        isA<TbFailure>().having(
          (e) => e.type,
          'type',
          TbFailureType.permissionDenied,
        ),
      ),
    );
    contract.expectAllConform(adapter);
  });

  test(
    'reportDashboardAction (STAR, VISIT) uses spec path and parses result',
    () async {
      adapter
        ..on(
          'GET',
          '/api/user/dashboards/dash-1/STAR',
          (_) => MockDioAdapter.jsonResponse({
            'last': const <Map<String, dynamic>>[],
            'starred': [
              {
                'id': 'dash-1',
                'title': 'Factory Overview',
                'starredAt': 1700000009000,
              },
            ],
          }),
        )
        ..on(
          'GET',
          '/api/user/dashboards/dash-1/VISIT',
          (_) => MockDioAdapter.jsonResponse({
            'last': [
              {
                'id': 'dash-1',
                'title': 'Factory Overview',
                'starred': true,
                'lastVisited': 1700000010000,
              },
            ],
            'starred': const <Map<String, dynamic>>[],
          }),
        );

      final starred = await repo.reportDashboardAction('dash-1', 'STAR');
      expect(starred.starred.single.id, 'dash-1');
      expect(starred.starred.single.timestamp, 1700000009000);

      final visited = await repo.reportDashboardAction('dash-1', 'VISIT');
      expect(visited.last.single.id, 'dash-1');
      expect(visited.last.single.timestamp, 1700000010000);
      expect(visited.starred, isEmpty);

      contract.expectAllConform(adapter);
      expect(
        contract.coveredOperations(adapter.capturedRequests),
        contains('GET /api/user/dashboards/{dashboardId}/{action}'),
      );
    },
  );

  test(
    'getDashboardById requests includeResources=true and parses configuration',
    () async {
      adapter.on(
        'GET',
        '/api/dashboard/dash-1',
        (_) => MockDioAdapter.jsonResponse({
          ...dashboardJson,
          'configuration': {
            'title': 'Factory Overview',
            'widgets': <String, dynamic>{},
          },
        }),
      );

      final dashboard = await repo.getDashboardById('dash-1');

      contract.expectAllConform(adapter);
      expect(adapter.capturedRequests.single.queryParameters, {
        'includeResources': true,
      });
      expect(dashboard.info.id, 'dash-1');
      expect(dashboard.info.title, 'Factory Overview');
      expect(dashboard.info.assignedCustomers, ['Acme']);
      expect(dashboard.configuration, {
        'title': 'Factory Overview',
        'widgets': <String, dynamic>{},
      });
      expect(
        contract.coveredOperations(adapter.capturedRequests),
        contains('GET /api/dashboard/{dashboardId}'),
      );
    },
  );
}
