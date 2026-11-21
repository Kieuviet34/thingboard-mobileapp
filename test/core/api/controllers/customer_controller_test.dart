import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:thingsboard_democloud_app/core/api/controllers/auth_controller.dart';
import 'package:thingsboard_democloud_app/core/api/controllers/customer_controller.dart';
import 'package:thingsboard_democloud_app/core/api/controllers/server_config_controller.dart';
import 'package:thingsboard_democloud_app/core/models/tb_failure.dart';

import '../../../helpers/fake_app_preferences.dart';
import '../../../helpers/fake_secure_storage.dart';
import '../../../helpers/fake_ws_channel.dart';
import '../../../helpers/mock_dio_adapter.dart';
import '../../../helpers/openapi_contract.dart';
import '../../../helpers/test_container.dart';

const _listPath = '/api/customerInfos/all';
const _legacyListPath = '/api/customers';

Map<String, dynamic> _customerJson(
  String id,
  String title, {
  String city = 'Berlin',
  String country = 'Germany',
}) {
  return {
    'id': {'entityType': 'CUSTOMER', 'id': id},
    'title': title,
    'city': city,
    'country': country,
    'email': 'ops@example.com',
    'createdTime': 1700000000000,
  };
}

Map<String, dynamic> _pageJson(
  List<Map<String, dynamic>> data, {
  required bool hasNext,
  required int totalElements,
}) {
  return {
    'data': data,
    'totalPages': 1,
    'totalElements': totalElements,
    'hasNext': hasNext,
  };
}

void main() {
  final contract = OpenApiContract.load();
  late MockDioAdapter adapter;
  late ProviderContainer container;

  setUp(() {
    adapter = MockDioAdapter();
    container = createTestContainer(
      overrides: [
        tbStorageProvider.overrideWithValue(FakeSecureStorage()),
        tbAppPreferencesProvider.overrideWithValue(FakeAppPreferences()),
        tbHttpClientAdapterProvider.overrideWithValue(adapter),
        wsChannelFactoryProvider.overrideWithValue(
          (_) => FakeWebSocketChannel(),
        ),
      ],
    );
  });

  group('CustomersNotifier (live HTTP)', () {
    test('initial load maps the customer list into data state', () async {
      adapter.on(
        'GET',
        _listPath,
        (_) => MockDioAdapter.jsonResponse(
          _pageJson(
            [
              _customerJson('cust-a', 'Alpha Corp'),
              _customerJson(
                'cust-b',
                'Beta Ltd',
                city: 'Hamburg',
                country: 'Germany',
              ),
            ],
            hasNext: false,
            totalElements: 2,
          ),
        ),
      );
      container.listen(customersListProvider(null), (_, _) {});

      final loaded = await container.read(customersListProvider(null).future);

      expect(loaded.items.map((c) => c.id), ['cust-a', 'cust-b']);
      expect(loaded.items.first.title, 'Alpha Corp');
      expect(loaded.items.first.locationSummary, 'Berlin, Germany');
      expect(loaded.page, 0);
      expect(loaded.hasNext, isFalse);
      expect(loaded.totalElements, 2);

      final request = adapter.capturedRequests.single;
      expect(request.queryParameters['page'], 0);
      expect(request.queryParameters['pageSize'], 20);
      expect(request.queryParameters['includeCustomers'], true);
      expect(request.queryParameters.containsKey('textSearch'), isFalse);
      contract.expectAllConform(adapter);
    });

    test('empty response yields an empty data state', () async {
      adapter.on(
        'GET',
        _listPath,
        (_) => MockDioAdapter.jsonResponse(
          _pageJson(const [], hasNext: false, totalElements: 0),
        ),
      );
      container.listen(customersListProvider(null), (_, _) {});

      final loaded = await container.read(customersListProvider(null).future);

      expect(loaded.items, isEmpty);
      expect(loaded.totalElements, 0);
      expect(container.read(customersListProvider(null)).hasError, isFalse);
    });

    test(
      'HTTP 403 is not masked by the legacy fallback and refresh recovers',
      () async {
        adapter.enqueue(
          'GET',
          _listPath,
          (_) => MockDioAdapter.jsonResponse({
            'status': 403,
            'errorCode': 20,
            'message': 'Forbidden',
          }, statusCode: 403),
        );
        adapter.on(
          'GET',
          _listPath,
          (_) => MockDioAdapter.jsonResponse(
            _pageJson(
              [_customerJson('cust-ok', 'Recovered Co')],
              hasNext: false,
              totalElements: 1,
            ),
          ),
        );
        container.listen(customersListProvider(null), (_, _) {});

        await expectLater(
          container.read(customersListProvider(null).future),
          throwsA(isA<TbFailure>()),
        );
        final failed = container.read(customersListProvider(null));
        final failure = failed.error! as TbFailure;
        expect(failure.type, TbFailureType.permissionDenied);
        expect(failure.statusCode, 403);
        expect(adapter.capturedRequests.map((r) => r.path), [
          _listPath,
        ], reason: 'a 403 must not trigger the /api/customers fallback');

        await container.read(customersListProvider(null).notifier).refresh();
        final recovered = container.read(customersListProvider(null));
        expect(recovered.hasError, isFalse);
        expect(recovered.requireValue.items.single.id, 'cust-ok');
        contract.expectAllConform(adapter);
      },
    );

    test(
      '404 on the list endpoint falls back to the legacy /api/customers',
      () async {
        // No handler for _listPath: MockDioAdapter answers 404 by default.
        adapter.on(
          'GET',
          _legacyListPath,
          (_) => MockDioAdapter.jsonResponse(
            _pageJson(
              [_customerJson('legacy-1', 'Legacy Customer')],
              hasNext: false,
              totalElements: 1,
            ),
          ),
        );
        container.listen(customersListProvider(null), (_, _) {});

        final loaded = await container.read(customersListProvider(null).future);

        expect(loaded.items.map((c) => c.title), ['Legacy Customer']);
        expect(adapter.capturedRequests.map((r) => r.path), [
          _listPath,
          _legacyListPath,
        ]);
        contract.expectAllConform(adapter);
      },
    );

    test(
      'loadNextPage appends pages and stops once hasNext is false',
      () async {
        adapter.on('GET', _listPath, (opts) {
          final page = opts.queryParameters['page'] as int;
          return MockDioAdapter.jsonResponse(
            page == 0
                ? _pageJson(
                    [
                      _customerJson('c0-a', 'Page0 A'),
                      _customerJson('c0-b', 'Page0 B'),
                    ],
                    hasNext: true,
                    totalElements: 3,
                  )
                : _pageJson(
                    [_customerJson('c1-a', 'Page1 A')],
                    hasNext: false,
                    totalElements: 3,
                  ),
          );
        });
        container.listen(customersListProvider(null), (_, _) {});
        await container.read(customersListProvider(null).future);
        final notifier = container.read(customersListProvider(null).notifier);

        await notifier.loadNextPage();
        final appended = container
            .read(customersListProvider(null))
            .requireValue;
        expect(appended.items.map((c) => c.id), ['c0-a', 'c0-b', 'c1-a']);
        expect(appended.page, 1);
        expect(appended.hasNext, isFalse);
        expect(appended.isLoadingMore, isFalse);
        expect(adapter.capturedRequests.last.queryParameters['page'], 1);

        final requestsBefore = adapter.capturedRequests.length;
        await notifier.loadNextPage();
        expect(adapter.capturedRequests.length, requestsBefore);
        expect(
          container.read(customersListProvider(null)).requireValue.items,
          hasLength(3),
        );
        contract.expectAllConform(adapter);
      },
    );

    test(
      'loadNextPage never starts a second page request while one is in flight',
      () async {
        final gate = Completer<void>();
        adapter.on('GET', _listPath, (opts) async {
          final page = opts.queryParameters['page'] as int;
          if (page == 0) {
            return MockDioAdapter.jsonResponse(
              _pageJson(
                [_customerJson('c0-a', 'Page0 A')],
                hasNext: true,
                totalElements: 2,
              ),
            );
          }
          await gate.future;
          return MockDioAdapter.jsonResponse(
            _pageJson(
              [_customerJson('c1-a', 'Page1 A')],
              hasNext: false,
              totalElements: 2,
            ),
          );
        });
        container.listen(customersListProvider(null), (_, _) {});
        await container.read(customersListProvider(null).future);
        final notifier = container.read(customersListProvider(null).notifier);

        final firstLoad = notifier.loadNextPage();
        await Future<void>.delayed(const Duration(milliseconds: 10));
        expect(
          container
              .read(customersListProvider(null))
              .requireValue
              .isLoadingMore,
          isTrue,
        );

        await notifier.loadNextPage();
        expect(
          adapter.capturedRequests.where((r) => r.queryParameters['page'] == 1),
          hasLength(1),
        );

        gate.complete();
        await firstLoad;

        final done = container.read(customersListProvider(null)).requireValue;
        expect(done.items.map((c) => c.id), ['c0-a', 'c1-a']);
        expect(done.isLoadingMore, isFalse);
        expect(done.hasNext, isFalse);
      },
    );

    test(
      'a failed next-page request keeps loaded items and can be retried',
      () async {
        adapter.on('GET', _listPath, (opts) {
          final page = opts.queryParameters['page'] as int;
          return MockDioAdapter.jsonResponse(
            page == 0
                ? _pageJson(
                    [_customerJson('c0-a', 'Page0 A')],
                    hasNext: true,
                    totalElements: 2,
                  )
                : _pageJson(
                    [_customerJson('c1-a', 'Page1 A')],
                    hasNext: false,
                    totalElements: 2,
                  ),
          );
        });
        container.listen(customersListProvider(null), (_, _) {});
        await container.read(customersListProvider(null).future);
        final notifier = container.read(customersListProvider(null).notifier);

        adapter.enqueue(
          'GET',
          _listPath,
          (_) => MockDioAdapter.jsonResponse({
            'status': 500,
            'message': 'Internal error',
          }, statusCode: 500),
        );
        await notifier.loadNextPage();

        var state = container.read(customersListProvider(null)).requireValue;
        expect(state.items.map((c) => c.id), ['c0-a']);
        expect(state.isLoadingMore, isFalse);
        expect(state.hasNext, isTrue);
        expect(state.loadMoreError?.type, TbFailureType.serverError);
        expect(state.loadMoreError?.statusCode, 500);

        await notifier.loadNextPage();
        state = container.read(customersListProvider(null)).requireValue;
        expect(state.items.map((c) => c.id), ['c0-a', 'c1-a']);
        expect(state.loadMoreError, isNull);
        expect(state.hasNext, isFalse);
        contract.expectAllConform(adapter);
      },
    );

    test(
      'an older slower next-page response is discarded after refresh',
      () async {
        final gate = Completer<void>();
        adapter.on('GET', _listPath, (opts) async {
          final page = opts.queryParameters['page'] as int;
          if (page == 0) {
            return MockDioAdapter.jsonResponse(
              _pageJson(
                [_customerJson('c0-a', 'Page0 A')],
                hasNext: true,
                totalElements: 2,
              ),
            );
          }
          await gate.future;
          return MockDioAdapter.jsonResponse(
            _pageJson(
              [_customerJson('stale-p1', 'Stale Page1')],
              hasNext: false,
              totalElements: 2,
            ),
          );
        });
        container.listen(customersListProvider(null), (_, _) {});
        await container.read(customersListProvider(null).future);
        final notifier = container.read(customersListProvider(null).notifier);

        final staleLoadMore = notifier.loadNextPage();
        await Future<void>.delayed(const Duration(milliseconds: 10));

        adapter.enqueue(
          'GET',
          _listPath,
          (_) => MockDioAdapter.jsonResponse(
            _pageJson(
              [_customerJson('fresh-p0', 'Fresh Page0')],
              hasNext: false,
              totalElements: 1,
            ),
          ),
        );
        await notifier.refresh();
        gate.complete();
        await staleLoadMore;

        final state = container.read(customersListProvider(null));
        expect(state.error, isNull);
        expect(state.requireValue.items.map((c) => c.id), ['fresh-p0']);
        expect(state.requireValue.page, 0);
        expect(state.requireValue.hasNext, isFalse);
      },
    );

    test(
      'an older slower refresh never overwrites a newer refresh result',
      () async {
        adapter.on(
          'GET',
          _listPath,
          (_) => MockDioAdapter.jsonResponse(
            _pageJson(
              [_customerJson('initial-a', 'Initial')],
              hasNext: false,
              totalElements: 1,
            ),
          ),
        );
        container.listen(customersListProvider(null), (_, _) {});
        await container.read(customersListProvider(null).future);
        final notifier = container.read(customersListProvider(null).notifier);

        final gate = Completer<void>();
        adapter.enqueue('GET', _listPath, (_) async {
          await gate.future;
          return MockDioAdapter.jsonResponse(
            _pageJson(
              [_customerJson('stale-a', 'Stale')],
              hasNext: false,
              totalElements: 1,
            ),
          );
        });
        adapter.enqueue(
          'GET',
          _listPath,
          (_) => MockDioAdapter.jsonResponse(
            _pageJson(
              [_customerJson('fresh-a', 'Fresh')],
              hasNext: false,
              totalElements: 1,
            ),
          ),
        );

        final staleRefresh = notifier.refresh();
        await Future<void>.delayed(const Duration(milliseconds: 10));
        await notifier.refresh();
        gate.complete();
        await staleRefresh;

        final state = container.read(customersListProvider(null));
        expect(
          state.error,
          isNull,
          reason:
              'stale refresh must not replace the newer result with an error',
        );
        expect(state.value?.items.map((c) => c.id), ['fresh-a']);
      },
    );

    test('a search query is sent trimmed and loads its own results', () async {
      adapter.on('GET', _listPath, (opts) {
        final search = opts.queryParameters['textSearch'] as String?;
        return MockDioAdapter.jsonResponse(
          _pageJson(
            [_customerJson('$search-1', 'Result for $search')],
            hasNext: false,
            totalElements: 1,
          ),
        );
      });
      container.listen(customersListProvider('acme'), (_, _) {});
      container.listen(customersListProvider('globex'), (_, _) {});

      final acme = await container.read(customersListProvider('acme').future);
      final globex = await container.read(
        customersListProvider('globex').future,
      );

      expect(acme.items.map((c) => c.id), ['acme-1']);
      expect(globex.items.map((c) => c.id), ['globex-1']);
      expect(
        adapter.capturedRequests.map((r) => r.queryParameters['textSearch']),
        ['acme', 'globex'],
      );
      contract.expectAllConform(adapter);
    });

    test(
      'a late response for a previous search never overwrites the newer search',
      () async {
        final acmeGate = Completer<void>();
        adapter.on('GET', _listPath, (opts) async {
          final search = opts.queryParameters['textSearch'] as String?;
          if (search == 'acme') await acmeGate.future;
          return MockDioAdapter.jsonResponse(
            _pageJson(
              [_customerJson('$search-1', 'Result for $search')],
              hasNext: false,
              totalElements: 1,
            ),
          );
        });
        container.listen(customersListProvider('acme'), (_, _) {});
        container.listen(customersListProvider('globex'), (_, _) {});

        final globex = await container.read(
          customersListProvider('globex').future,
        );
        acmeGate.complete();
        await container.read(customersListProvider('acme').future);

        expect(globex.items.map((c) => c.id), ['globex-1']);
        expect(
          container
              .read(customersListProvider('globex'))
              .requireValue
              .items
              .map((c) => c.id),
          ['globex-1'],
        );
      },
    );

    test('customer details load from the info endpoint', () async {
      adapter.on(
        'GET',
        '/api/customer/info/cust-a',
        (_) => MockDioAdapter.jsonResponse({
          'id': {'entityType': 'CUSTOMER', 'id': 'cust-a'},
          'title': 'Alpha Corp',
          'city': 'Berlin',
          'country': 'Germany',
          'email': 'ops@example.com',
          'parentCustomerId': {'entityType': 'CUSTOMER', 'id': 'cust-root'},
        }),
      );
      container.listen(customerDetailsProvider('cust-a'), (_, _) {});

      final details = await container.read(
        customerDetailsProvider('cust-a').future,
      );

      expect(details.id, 'cust-a');
      expect(details.title, 'Alpha Corp');
      expect(details.email, 'ops@example.com');
      expect(details.parentCustomerId, 'cust-root');
      contract.expectAllConform(adapter);
    });

    test('customer details fall back to the legacy endpoint on 404', () async {
      adapter.on(
        'GET',
        '/api/customer/cust-b',
        (_) => MockDioAdapter.jsonResponse({
          'id': {'entityType': 'CUSTOMER', 'id': 'cust-b'},
          'title': 'Legacy Beta',
        }),
      );
      container.listen(customerDetailsProvider('cust-b'), (_, _) {});

      final details = await container.read(
        customerDetailsProvider('cust-b').future,
      );

      expect(details.title, 'Legacy Beta');
      expect(adapter.capturedRequests.map((r) => r.path), [
        '/api/customer/info/cust-b',
        '/api/customer/cust-b',
      ]);
      contract.expectAllConform(adapter);
    });

    test('customer details surface 403 without falling back', () async {
      adapter.enqueue(
        'GET',
        '/api/customer/info/cust-c',
        (_) => MockDioAdapter.jsonResponse({
          'status': 403,
          'errorCode': 20,
          'message': 'Forbidden',
        }, statusCode: 403),
      );
      container.listen(customerDetailsProvider('cust-c'), (_, _) {});

      await expectLater(
        container.read(customerDetailsProvider('cust-c').future),
        throwsA(
          isA<TbFailure>().having(
            (f) => f.type,
            'type',
            TbFailureType.permissionDenied,
          ),
        ),
      );
      expect(adapter.capturedRequests.map((r) => r.path), [
        '/api/customer/info/cust-c',
      ]);
    });
  });

  group('CustomersNotifier & customerDetailsProvider (demo mode)', () {
    test('seeded customers are listed and searchable offline', () async {
      await container.read(authProvider.notifier).loginDemo();
      container.listen(customersListProvider(null), (_, _) {});
      container.listen(customersListProvider('germany'), (_, _) {});

      final all = await container.read(customersListProvider(null).future);
      expect(all.items.map((c) => c.title), [
        'Acme Smart Buildings',
        'Global Cold Logistics',
        'Metro Energy Grid',
        'City Water Works',
      ]);
      expect(all.hasNext, isFalse);
      expect(adapter.capturedRequests, isEmpty);

      final germany = await container.read(
        customersListProvider('germany').future,
      );
      expect(germany.items.map((c) => c.id), ['cust-2']);
      expect(germany.totalElements, 1);
    });

    test(
      'demo customer details resolve by id and unknown id is notFound',
      () async {
        await container.read(authProvider.notifier).loginDemo();
        container.listen(customerDetailsProvider('cust-2'), (_, _) {});
        container.listen(customerDetailsProvider('cust-999'), (_, _) {});

        final details = await container.read(
          customerDetailsProvider('cust-2').future,
        );
        expect(details.title, 'Global Cold Logistics');
        expect(details.email, 'fleet@globalcold.de');

        await expectLater(
          container.read(customerDetailsProvider('cust-999').future),
          throwsA(
            isA<TbFailure>().having(
              (f) => f.type,
              'type',
              TbFailureType.notFound,
            ),
          ),
        );
      },
    );
  });
}
