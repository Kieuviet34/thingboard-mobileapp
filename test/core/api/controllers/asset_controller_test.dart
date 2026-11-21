import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:thingsboard_democloud_app/core/api/controllers/asset_controller.dart';
import 'package:thingsboard_democloud_app/core/api/controllers/auth_controller.dart';
import 'package:thingsboard_democloud_app/core/api/controllers/server_config_controller.dart';
import 'package:thingsboard_democloud_app/core/models/asset_models.dart';
import 'package:thingsboard_democloud_app/core/models/entity_id.dart';
import 'package:thingsboard_democloud_app/core/models/tb_failure.dart';

import '../../../helpers/fake_app_preferences.dart';
import '../../../helpers/fake_secure_storage.dart';
import '../../../helpers/fake_ws_channel.dart';
import '../../../helpers/mock_dio_adapter.dart';
import '../../../helpers/openapi_contract.dart';
import '../../../helpers/test_container.dart';

const _listPath = '/api/assetInfos/all';
const _legacyListPath = '/api/tenant/assetInfos';
const _defaultQuery = TbAssetQuery();

Map<String, dynamic> _assetJson(
  String id,
  String name, {
  String type = 'Building',
}) {
  return {
    'id': {'entityType': 'ASSET', 'id': id},
    'name': name,
    'type': type,
    'label': 'Label $name',
    'ownerName': 'Acme Smart Buildings',
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

  group('AssetsNotifier (live HTTP)', () {
    test('initial load maps the asset list into data state', () async {
      adapter.on(
        'GET',
        _listPath,
        (_) => MockDioAdapter.jsonResponse(
          _pageJson(
            [
              _assetJson('asset-a', 'Warehouse North'),
              _assetJson('asset-b', 'Substation South', type: 'Substation'),
            ],
            hasNext: false,
            totalElements: 2,
          ),
        ),
      );
      container.listen(assetsListProvider(_defaultQuery), (_, _) {});

      final loaded = await container.read(
        assetsListProvider(_defaultQuery).future,
      );

      expect(loaded.items.map((a) => a.id), ['asset-a', 'asset-b']);
      expect(loaded.items.last.type, 'Substation');
      expect(loaded.items.first.ownerName, 'Acme Smart Buildings');
      expect(loaded.page, 0);
      expect(loaded.hasNext, isFalse);
      expect(loaded.totalElements, 2);

      final request = adapter.capturedRequests.single;
      expect(request.queryParameters['page'], 0);
      expect(request.queryParameters['pageSize'], 20);
      expect(request.queryParameters['includeCustomers'], true);
      expect(request.queryParameters.containsKey('assetProfileId'), isFalse);
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
      container.listen(assetsListProvider(_defaultQuery), (_, _) {});

      final loaded = await container.read(
        assetsListProvider(_defaultQuery).future,
      );

      expect(loaded.items, isEmpty);
      expect(loaded.totalElements, 0);
      expect(
        container.read(assetsListProvider(_defaultQuery)).hasError,
        isFalse,
      );
    });

    test('filters are forwarded and the search text is trimmed', () async {
      adapter.on(
        'GET',
        _listPath,
        (_) => MockDioAdapter.jsonResponse(
          _pageJson(
            [
              _assetJson(
                'asset-3',
                'Solar Substation North',
                type: 'Substation',
              ),
            ],
            hasNext: false,
            totalElements: 1,
          ),
        ),
      );
      const filter = TbAssetQuery(
        assetProfileId: 'ap-3',
        textSearch: '  solar  ',
      );
      container.listen(assetsListProvider(filter), (_, _) {});

      final loaded = await container.read(assetsListProvider(filter).future);

      expect(loaded.items.map((a) => a.name), ['Solar Substation North']);
      final request = adapter.capturedRequests.single;
      expect(request.queryParameters['assetProfileId'], 'ap-3');
      expect(request.queryParameters['textSearch'], 'solar');
      contract.expectAllConform(adapter);
    });

    test('a different search query loads its own results', () async {
      adapter.on('GET', _listPath, (opts) {
        final search = opts.queryParameters['textSearch'] as String;
        return MockDioAdapter.jsonResponse(
          _pageJson(
            [_assetJson('$search-1', 'Result for $search')],
            hasNext: false,
            totalElements: 1,
          ),
        );
      });
      const alpha = TbAssetQuery(textSearch: 'alpha');
      const beta = TbAssetQuery(textSearch: 'beta');
      container.listen(assetsListProvider(alpha), (_, _) {});
      container.listen(assetsListProvider(beta), (_, _) {});

      final alphaLoaded = await container.read(
        assetsListProvider(alpha).future,
      );
      final betaLoaded = await container.read(assetsListProvider(beta).future);

      expect(alphaLoaded.items.map((a) => a.id), ['alpha-1']);
      expect(betaLoaded.items.map((a) => a.id), ['beta-1']);
      expect(
        adapter.capturedRequests.map((r) => r.queryParameters['textSearch']),
        ['alpha', 'beta'],
      );
    });

    test(
      'a late response for a previous search never overwrites the newer search',
      () async {
        const alpha = TbAssetQuery(textSearch: 'alpha');
        const beta = TbAssetQuery(textSearch: 'beta');
        final alphaGate = Completer<void>();
        adapter.on('GET', _listPath, (opts) async {
          final search = opts.queryParameters['textSearch'] as String;
          if (search == 'alpha') await alphaGate.future;
          return MockDioAdapter.jsonResponse(
            _pageJson(
              [_assetJson('$search-1', 'Result for $search')],
              hasNext: false,
              totalElements: 1,
            ),
          );
        });
        container.listen(assetsListProvider(alpha), (_, _) {});
        container.listen(assetsListProvider(beta), (_, _) {});

        final betaLoaded = await container.read(
          assetsListProvider(beta).future,
        );
        alphaGate.complete();
        await container.read(assetsListProvider(alpha).future);

        expect(betaLoaded.items.map((a) => a.id), ['beta-1']);
        expect(
          container
              .read(assetsListProvider(beta))
              .requireValue
              .items
              .map((a) => a.id),
          ['beta-1'],
        );
      },
    );

    test('HTTP 403 surfaces a TbFailure and refresh recovers', () async {
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
            [_assetJson('asset-ok', 'Recovered Asset')],
            hasNext: false,
            totalElements: 1,
          ),
        ),
      );
      container.listen(assetsListProvider(_defaultQuery), (_, _) {});

      await expectLater(
        container.read(assetsListProvider(_defaultQuery).future),
        throwsA(isA<TbFailure>()),
      );
      final failure =
          container.read(assetsListProvider(_defaultQuery)).error! as TbFailure;
      expect(failure.type, TbFailureType.permissionDenied);
      expect(failure.statusCode, 403);

      await container
          .read(assetsListProvider(_defaultQuery).notifier)
          .refresh();
      final recovered = container.read(assetsListProvider(_defaultQuery));
      expect(recovered.hasError, isFalse);
      expect(recovered.requireValue.items.single.id, 'asset-ok');
      contract.expectAllConform(adapter);
    });

    test(
      '404 on the list endpoint falls back to /api/tenant/assetInfos',
      () async {
        adapter.on(
          'GET',
          _legacyListPath,
          (_) => MockDioAdapter.jsonResponse(
            _pageJson(
              [_assetJson('legacy-1', 'Legacy Asset')],
              hasNext: false,
              totalElements: 1,
            ),
          ),
        );
        container.listen(assetsListProvider(_defaultQuery), (_, _) {});

        final loaded = await container.read(
          assetsListProvider(_defaultQuery).future,
        );

        expect(loaded.items.map((a) => a.name), ['Legacy Asset']);
        expect(adapter.capturedRequests.map((r) => r.path), [
          _listPath,
          _legacyListPath,
        ]);
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
                      _assetJson('a0-a', 'Page0 A'),
                      _assetJson('a0-b', 'Page0 B'),
                    ],
                    hasNext: true,
                    totalElements: 3,
                  )
                : _pageJson(
                    [_assetJson('a1-a', 'Page1 A')],
                    hasNext: false,
                    totalElements: 3,
                  ),
          );
        });
        container.listen(assetsListProvider(_defaultQuery), (_, _) {});
        await container.read(assetsListProvider(_defaultQuery).future);
        final notifier = container.read(
          assetsListProvider(_defaultQuery).notifier,
        );

        await notifier.loadNextPage();
        final appended = container
            .read(assetsListProvider(_defaultQuery))
            .requireValue;
        expect(appended.items.map((a) => a.id), ['a0-a', 'a0-b', 'a1-a']);
        expect(appended.page, 1);
        expect(appended.hasNext, isFalse);
        expect(appended.isLoadingMore, isFalse);
        expect(adapter.capturedRequests.last.queryParameters['page'], 1);

        final requestsBefore = adapter.capturedRequests.length;
        await notifier.loadNextPage();
        expect(adapter.capturedRequests.length, requestsBefore);
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
                [_assetJson('a0-a', 'Page0 A')],
                hasNext: true,
                totalElements: 2,
              ),
            );
          }
          await gate.future;
          return MockDioAdapter.jsonResponse(
            _pageJson(
              [_assetJson('a1-a', 'Page1 A')],
              hasNext: false,
              totalElements: 2,
            ),
          );
        });
        container.listen(assetsListProvider(_defaultQuery), (_, _) {});
        await container.read(assetsListProvider(_defaultQuery).future);
        final notifier = container.read(
          assetsListProvider(_defaultQuery).notifier,
        );

        final firstLoad = notifier.loadNextPage();
        await Future<void>.delayed(const Duration(milliseconds: 10));
        expect(
          container
              .read(assetsListProvider(_defaultQuery))
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

        final done = container
            .read(assetsListProvider(_defaultQuery))
            .requireValue;
        expect(done.items.map((a) => a.id), ['a0-a', 'a1-a']);
        expect(done.isLoadingMore, isFalse);
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
                    [_assetJson('a0-a', 'Page0 A')],
                    hasNext: true,
                    totalElements: 2,
                  )
                : _pageJson(
                    [_assetJson('a1-a', 'Page1 A')],
                    hasNext: false,
                    totalElements: 2,
                  ),
          );
        });
        container.listen(assetsListProvider(_defaultQuery), (_, _) {});
        await container.read(assetsListProvider(_defaultQuery).future);
        final notifier = container.read(
          assetsListProvider(_defaultQuery).notifier,
        );

        adapter.enqueue(
          'GET',
          _listPath,
          (_) => MockDioAdapter.jsonResponse({
            'status': 500,
            'message': 'Internal error',
          }, statusCode: 500),
        );
        await notifier.loadNextPage();

        var state = container
            .read(assetsListProvider(_defaultQuery))
            .requireValue;
        expect(state.items.map((a) => a.id), ['a0-a']);
        expect(state.isLoadingMore, isFalse);
        expect(state.hasNext, isTrue);
        expect(state.loadMoreError?.type, TbFailureType.serverError);
        expect(state.loadMoreError?.statusCode, 500);

        await notifier.loadNextPage();
        state = container.read(assetsListProvider(_defaultQuery)).requireValue;
        expect(state.items.map((a) => a.id), ['a0-a', 'a1-a']);
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
                [_assetJson('a0-a', 'Page0 A')],
                hasNext: true,
                totalElements: 2,
              ),
            );
          }
          await gate.future;
          return MockDioAdapter.jsonResponse(
            _pageJson(
              [_assetJson('stale-p1', 'Stale Page1')],
              hasNext: false,
              totalElements: 2,
            ),
          );
        });
        container.listen(assetsListProvider(_defaultQuery), (_, _) {});
        await container.read(assetsListProvider(_defaultQuery).future);
        final notifier = container.read(
          assetsListProvider(_defaultQuery).notifier,
        );

        final staleLoadMore = notifier.loadNextPage();
        await Future<void>.delayed(const Duration(milliseconds: 10));

        adapter.enqueue(
          'GET',
          _listPath,
          (_) => MockDioAdapter.jsonResponse(
            _pageJson(
              [_assetJson('fresh-p0', 'Fresh Page0')],
              hasNext: false,
              totalElements: 1,
            ),
          ),
        );
        await notifier.refresh();
        gate.complete();
        await staleLoadMore;

        final state = container.read(assetsListProvider(_defaultQuery));
        expect(state.error, isNull);
        expect(state.requireValue.items.map((a) => a.id), ['fresh-p0']);
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
              [_assetJson('initial-a', 'Initial')],
              hasNext: false,
              totalElements: 1,
            ),
          ),
        );
        container.listen(assetsListProvider(_defaultQuery), (_, _) {});
        await container.read(assetsListProvider(_defaultQuery).future);
        final notifier = container.read(
          assetsListProvider(_defaultQuery).notifier,
        );

        final gate = Completer<void>();
        adapter.enqueue('GET', _listPath, (_) async {
          await gate.future;
          return MockDioAdapter.jsonResponse(
            _pageJson(
              [_assetJson('stale-a', 'Stale')],
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
              [_assetJson('fresh-a', 'Fresh')],
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

        final state = container.read(assetsListProvider(_defaultQuery));
        expect(
          state.error,
          isNull,
          reason:
              'stale refresh must not replace the newer result with an error',
        );
        expect(state.value?.items.map((a) => a.id), ['fresh-a']);
      },
    );

    test(
      'asset details load from the info endpoint and 404 is not retried',
      () async {
        adapter.on(
          'GET',
          '/api/asset/info/asset-a',
          (_) => MockDioAdapter.jsonResponse({
            'id': {'entityType': 'ASSET', 'id': 'asset-a'},
            'name': 'Warehouse North',
            'type': 'Warehouse',
            'label': 'Frozen Goods Facility',
            'assetProfileId': {'entityType': 'ASSET_PROFILE', 'id': 'ap-2'},
            'customerId': {'entityType': 'CUSTOMER', 'id': 'cust-2'},
          }),
        );
        adapter.on(
          'GET',
          '/api/asset/info/missing',
          (_) => MockDioAdapter.jsonResponse({
            'status': 404,
            'message': 'Asset not found',
          }, statusCode: 404),
        );
        container.listen(assetDetailsProvider('asset-a'), (_, _) {});
        container.listen(assetDetailsProvider('missing'), (_, _) {});

        final details = await container.read(
          assetDetailsProvider('asset-a').future,
        );
        expect(details.name, 'Warehouse North');
        expect(details.assetProfileId, 'ap-2');
        expect(details.customerId, 'cust-2');

        await expectLater(
          container.read(assetDetailsProvider('missing').future),
          throwsA(
            isA<TbFailure>().having(
              (f) => f.type,
              'type',
              TbFailureType.notFound,
            ),
          ),
        );
        expect(
          adapter.capturedRequests.where((r) => r.path.endsWith('/missing')),
          hasLength(1),
        );
        contract.expectAllConform(adapter);
      },
    );

    test('asset profiles are fetched with a 50-item page', () async {
      adapter.on(
        'GET',
        '/api/assetProfileInfos',
        (_) => MockDioAdapter.jsonResponse(
          _pageJson(
            [
              {
                'id': {'entityType': 'ASSET_PROFILE', 'id': 'ap-1'},
                'name': 'Building',
              },
              {
                'id': {'entityType': 'ASSET_PROFILE', 'id': 'ap-2'},
                'name': 'Warehouse',
              },
            ],
            hasNext: false,
            totalElements: 2,
          ),
        ),
      );
      container.listen(assetProfilesProvider, (_, _) {});

      final profiles = await container.read(assetProfilesProvider.future);

      expect(profiles.map((p) => p.id), ['ap-1', 'ap-2']);
      expect(profiles.map((p) => p.name), ['Building', 'Warehouse']);
      final request = adapter.capturedRequests.single;
      expect(request.queryParameters['pageSize'], 50);
      expect(request.queryParameters['page'], 0);
      contract.expectAllConform(adapter);
    });

    test('entity relations resolve outgoing and incoming directions', () async {
      final relationJson = [
        {
          'from': {'entityType': 'ASSET', 'id': 'asset-1'},
          'to': {'entityType': 'DEVICE', 'id': 'dev-1'},
          'type': 'Contains',
          'typeGroup': 'COMMON',
          'fromName': 'Headquarters Building A',
          'toName': 'Thermostat-Floor-1',
        },
      ];
      adapter.on(
        'GET',
        '/api/relations/info/from/ASSET/asset-1',
        (_) => MockDioAdapter.jsonResponse(relationJson),
      );
      adapter.on(
        'GET',
        '/api/relations/info/to/ASSET/asset-1',
        (_) => MockDioAdapter.jsonResponse(const <dynamic>[]),
      );
      const hq = EntityId(entityType: EntityType.asset, id: 'asset-1');
      container.listen(
        entityRelationsProvider((entity: hq, outgoing: true)),
        (_, _) {},
      );
      container.listen(
        entityRelationsProvider((entity: hq, outgoing: false)),
        (_, _) {},
      );

      final outgoing = await container.read(
        entityRelationsProvider((entity: hq, outgoing: true)).future,
      );
      final incoming = await container.read(
        entityRelationsProvider((entity: hq, outgoing: false)).future,
      );

      expect(outgoing.single.toName, 'Thermostat-Floor-1');
      expect(outgoing.single.to.entityType, EntityType.device);
      expect(incoming, isEmpty);
      contract.expectAllConform(adapter);
    });
  });

  group('Asset controller providers (demo mode)', () {
    test('seeded assets are listed and searchable offline', () async {
      await container.read(authProvider.notifier).loginDemo();
      const solar = TbAssetQuery(textSearch: 'solar');
      container.listen(assetsListProvider(_defaultQuery), (_, _) {});
      container.listen(assetsListProvider(solar), (_, _) {});

      final all = await container.read(
        assetsListProvider(_defaultQuery).future,
      );
      expect(all.items.map((a) => a.id), [
        'asset-1',
        'asset-2',
        'asset-3',
        'asset-4',
      ]);
      expect(all.hasNext, isFalse);
      expect(adapter.capturedRequests, isEmpty);

      final solarLoaded = await container.read(
        assetsListProvider(solar).future,
      );
      expect(solarLoaded.items.map((a) => a.name), ['Solar Substation North']);
    });

    test('demo profiles are derived from the distinct asset types', () async {
      await container.read(authProvider.notifier).loginDemo();
      container.listen(assetProfilesProvider, (_, _) {});

      final profiles = await container.read(assetProfilesProvider.future);

      expect(profiles.map((p) => p.name), [
        'Building',
        'Warehouse',
        'Substation',
        'Water Station',
      ]);
    });

    test(
      'demo relations return the seeded outgoing links of an asset',
      () async {
        await container.read(authProvider.notifier).loginDemo();
        const hq = EntityId(entityType: EntityType.asset, id: 'asset-1');
        container.listen(
          entityRelationsProvider((entity: hq, outgoing: true)),
          (_, _) {},
        );

        final relations = await container.read(
          entityRelationsProvider((entity: hq, outgoing: true)).future,
        );

        expect(relations.map((r) => r.toName), [
          'Thermostat-Floor-1',
          'Thermostat-Floor-3',
        ]);
      },
    );

    test(
      'demo asset details resolve by id and unknown id is notFound',
      () async {
        await container.read(authProvider.notifier).loginDemo();
        container.listen(assetDetailsProvider('asset-2'), (_, _) {});
        container.listen(assetDetailsProvider('asset-999'), (_, _) {});

        final details = await container.read(
          assetDetailsProvider('asset-2').future,
        );
        expect(details.name, 'Cold Storage Warehouse #2');
        expect(details.type, 'Warehouse');

        await expectLater(
          container.read(assetDetailsProvider('asset-999').future),
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
