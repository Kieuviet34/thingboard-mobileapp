import 'package:flutter_test/flutter_test.dart';
import 'package:thingsboard_democloud_app/core/api/client/tb_api_client.dart';
import 'package:thingsboard_democloud_app/core/api/repositories/asset_repository.dart';
import 'package:thingsboard_democloud_app/core/models/models.dart';

import '../../../../helpers/fake_secure_storage.dart';
import '../../../../helpers/mock_dio_adapter.dart';
import '../../../../helpers/openapi_contract.dart';

/// Contract test: every request `RestAssetRepository` sends must exist in the
/// ThingsBoard 4.4.x OpenAPI, and every response shape must parse correctly.
void main() {
  late MockDioAdapter adapter;
  late RestAssetRepository repo;
  final contract = OpenApiContract.load();

  // Shape: AssetInfo (spec schema).
  const assetJson = <String, dynamic>{
    'id': {'entityType': 'ASSET', 'id': 'a-1'},
    'createdTime': 1700000000000,
    'tenantId': {'entityType': 'TENANT', 'id': 't-1'},
    'customerId': {'entityType': 'CUSTOMER', 'id': 'c-1'},
    'name': 'Pump 1',
    'type': 'Pump',
    'label': 'Line A',
    'assetProfileId': {'entityType': 'ASSET_PROFILE', 'id': 'ap-1'},
    'version': 1,
    'ownerName': 'Acme',
    'groups': <dynamic>[],
    'ownerId': {'entityType': 'CUSTOMER', 'id': 'c-1'},
    'additionalInfo': {'description': 'Feed pump'},
  };

  // Shape: AssetProfileInfo (spec schema).
  const assetProfileJson = <String, dynamic>{
    'id': {'entityType': 'ASSET_PROFILE', 'id': 'ap-1'},
    'tenantId': {'entityType': 'TENANT', 'id': 't-1'},
    'name': 'Pump',
    'image': 'pump.png',
    'defaultDashboardId': {'entityType': 'DASHBOARD', 'id': 'db-2'},
  };

  Map<String, dynamic> page(List<Map<String, dynamic>> items) => {
    'data': items,
    'totalPages': 1,
    'totalElements': items.length,
    'hasNext': false,
  };

  setUp(() {
    adapter = MockDioAdapter();
    repo = RestAssetRepository(
      client: TbApiClient(
        baseUrl: 'https://thingsboard.democloud.xyz/',
        storage: FakeSecureStorage(),
        httpClientAdapter: adapter,
      ),
    );
  });

  test(
    'getAssets (all filters) sends spec-valid query and parses page',
    () async {
      adapter.on(
        'GET',
        '/api/assetInfos/all',
        (_) => MockDioAdapter.jsonResponse(page([assetJson])),
      );

      final result = await repo.getAssets(
        const PageQuery(
          page: 1,
          pageSize: 5,
          textSearch: 'pump',
          sortProperty: 'name',
          sortOrder: SortOrder.asc,
        ),
        const TbAssetQuery(assetProfileId: 'ap-1', textSearch: 'pump'),
      );

      contract.expectAllConform(adapter);
      expect(adapter.capturedRequests.single.queryParameters, {
        'page': 1,
        'pageSize': 5,
        'textSearch': 'pump',
        'sortProperty': 'name',
        'sortOrder': 'ASC',
        'includeCustomers': true,
        'assetProfileId': 'ap-1',
      });
      final asset = result.data.single;
      expect(asset.id, 'a-1');
      expect(asset.name, 'Pump 1');
      expect(asset.type, 'Pump');
      expect(asset.label, 'Line A');
      expect(asset.assetProfileId, 'ap-1');
      expect(asset.customerId, 'c-1');
      expect(asset.ownerName, 'Acme');
      expect(asset.createdTime, 1700000000000);
      expect(result.totalElements, 1);
      expect(result.hasNext, isFalse);
      expect(
        contract.coveredOperations(adapter.capturedRequests),
        contains('GET /api/assetInfos/all'),
      );
    },
  );

  test('getAssets drops blank filters and uses default paging', () async {
    adapter.on(
      'GET',
      '/api/assetInfos/all',
      (_) => MockDioAdapter.jsonResponse(page(const [])),
    );

    await repo.getAssets(
      const PageQuery(),
      const TbAssetQuery(assetProfileId: '', textSearch: '   '),
    );

    contract.expectAllConform(adapter);
    expect(adapter.capturedRequests.single.queryParameters, {
      'page': 0,
      'pageSize': 20,
      'sortProperty': 'createdTime',
      'sortOrder': 'DESC',
      'includeCustomers': true,
    });
  });

  test(
    'getAssets falls back to /api/tenant/assetInfos only on HTTP 404',
    () async {
      adapter
        ..enqueue(
          'GET',
          '/api/assetInfos/all',
          (_) => MockDioAdapter.jsonResponse({'status': 404}, statusCode: 404),
        )
        ..on(
          'GET',
          '/api/tenant/assetInfos',
          (_) => MockDioAdapter.jsonResponse(page([assetJson])),
        );

      final result = await repo.getAssets(
        const PageQuery(),
        const TbAssetQuery(),
      );

      contract.expectAllConform(adapter);
      expect(adapter.capturedRequests.map((r) => r.path).toList(), [
        '/api/assetInfos/all',
        '/api/tenant/assetInfos',
      ]);
      expect(result.data.single.id, 'a-1');
      expect(
        contract.coveredOperations(adapter.capturedRequests),
        contains('GET /api/assetInfos/all'),
      );
    },
  );

  test('getAssetInfo uses /api/asset/info/{assetId}', () async {
    adapter.on(
      'GET',
      '/api/asset/info/a-1',
      (_) => MockDioAdapter.jsonResponse(assetJson),
    );

    final asset = await repo.getAssetInfo('a-1');

    contract.expectAllConform(adapter);
    expect(asset.id, 'a-1');
    expect(asset.name, 'Pump 1');
    expect(asset.assetProfileId, 'ap-1');
    expect(asset.ownerName, 'Acme');
    expect(
      contract.coveredOperations(adapter.capturedRequests),
      contains('GET /api/asset/info/{assetId}'),
    );
  });

  test('getAssetProfiles sends spec query and parses profiles', () async {
    adapter.on(
      'GET',
      '/api/assetProfileInfos',
      (_) => MockDioAdapter.jsonResponse(page([assetProfileJson])),
    );

    final result = await repo.getAssetProfiles(
      const PageQuery(textSearch: 'Pump'),
    );

    contract.expectAllConform(adapter);
    expect(adapter.capturedRequests.single.queryParameters, {
      'page': 0,
      'pageSize': 20,
      'textSearch': 'Pump',
      'sortProperty': 'createdTime',
      'sortOrder': 'DESC',
    });
    final profile = result.data.single;
    expect(profile.id, 'ap-1');
    expect(profile.name, 'Pump');
    expect(profile.image, 'pump.png');
    expect(profile.defaultDashboardId, 'db-2');
    expect(
      contract.coveredOperations(adapter.capturedRequests),
      contains('GET /api/assetProfileInfos'),
    );
  });

  test(
    'getRelations (default, outgoing) uses /api/relations/info/from/{type}/{id}',
    () async {
      adapter.on(
        'GET',
        '/api/relations/info/from/ASSET/a-1',
        (_) => MockDioAdapter.jsonResponse([
          {
            'from': {'entityType': 'ASSET', 'id': 'a-1'},
            'to': {'entityType': 'DEVICE', 'id': 'd-1'},
            'type': 'Contains',
            'typeGroup': 'COMMON',
            'version': 1,
            'fromName': 'Pump 1',
            'toName': 'Sensor 1',
          },
        ]),
      );

      final relations = await repo.getRelations(
        const EntityId(entityType: EntityType.asset, id: 'a-1'),
      );

      contract.expectAllConform(adapter);
      expect(relations, hasLength(1));
      final relation = relations.single;
      expect(
        relation.from,
        const EntityId(entityType: EntityType.asset, id: 'a-1'),
      );
      expect(
        relation.to,
        const EntityId(entityType: EntityType.device, id: 'd-1'),
      );
      expect(relation.type, 'Contains');
      expect(relation.typeGroup, 'COMMON');
      expect(relation.fromName, 'Pump 1');
      expect(relation.toName, 'Sensor 1');
      expect(
        contract.coveredOperations(adapter.capturedRequests),
        contains('GET /api/relations/info/from/{fromType}/{fromId}'),
      );
    },
  );

  test(
    'getRelations (outgoing: false) uses /api/relations/info/to/{type}/{id}',
    () async {
      adapter.on(
        'GET',
        '/api/relations/info/to/DEVICE/d-1',
        (_) => MockDioAdapter.jsonResponse([
          {
            'from': {'entityType': 'ASSET', 'id': 'a-1'},
            'to': {'entityType': 'DEVICE', 'id': 'd-1'},
            'type': 'Contains',
            'typeGroup': 'COMMON',
            'version': 1,
            'fromName': 'Pump 1',
            'toName': 'Sensor 1',
          },
        ]),
      );

      final relations = await repo.getRelations(
        const EntityId(entityType: EntityType.device, id: 'd-1'),
        outgoing: false,
      );

      contract.expectAllConform(adapter);
      expect(relations.single.from.id, 'a-1');
      expect(relations.single.to.id, 'd-1');
      expect(relations.single.fromName, 'Pump 1');
      expect(
        contract.coveredOperations(adapter.capturedRequests),
        contains('GET /api/relations/info/to/{toType}/{toId}'),
      );
    },
  );
}
