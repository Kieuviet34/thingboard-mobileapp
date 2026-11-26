import 'package:flutter_test/flutter_test.dart';
import 'package:thingsboard_democloud_app/core/api/client/tb_api_client.dart';
import 'package:thingsboard_democloud_app/core/api/repositories/asset_repository.dart';
import 'package:thingsboard_democloud_app/core/api/repositories/customer_repository.dart';
import 'package:thingsboard_democloud_app/core/api/repositories/dashboard_repository.dart';
import 'package:thingsboard_democloud_app/core/api/repositories/device_repository.dart';
import 'package:thingsboard_democloud_app/core/api/repositories/tenant_repository.dart';
import 'package:thingsboard_democloud_app/core/models/models.dart';

import '../../../helpers/fake_secure_storage.dart';
import '../../../helpers/mock_dio_adapter.dart';

void main() {
  late MockDioAdapter adapter;
  late FakeSecureStorage storage;
  late TbApiClient client;

  setUp(() {
    adapter = MockDioAdapter();
    storage = FakeSecureStorage();
    client = TbApiClient(
      baseUrl: 'https://thingsboard.democloud.xyz/',
      storage: storage,
      httpClientAdapter: adapter,
    );
  });

  group('TenantController & TenantProfileController routes (PE 4.4 + TB 3.3)', () {
    test(
      'getTenantInfo falls back to /api/tenant/{id} on 404, never masks 403, and supports save/delete/list',
      () async {
        final repo = RestTenantRepository(client: client);

        // 1) 404 on /api/tenant/info/t-1 -> falls back to /api/tenant/t-1
        adapter.enqueue(
          'GET',
          '/api/tenant/info/t-1',
          (_) => MockDioAdapter.jsonResponse({'status': 404}, statusCode: 404),
        );
        adapter.on(
          'GET',
          '/api/tenant/t-1',
          (_) => MockDioAdapter.jsonResponse({
            'id': {'entityType': 'TENANT', 'id': 't-1'},
            'title': 'DemoCloud IoT',
            'region': 'ap-southeast-1',
            'email': 'tenant@democloud.xyz',
            'country': 'VN',
            'city': 'Hanoi',
            'tenantProfileId': {'entityType': 'TENANT_PROFILE', 'id': 'tp-1'},
          }),
        );

        final info = await repo.getTenantInfo('t-1');
        expect(info.id, 't-1');
        expect(info.title, 'DemoCloud IoT');
        expect(info.tenantProfileId, 'tp-1');
        expect(info.active, isTrue);

        // 2) 403 on /api/tenant/info/t-forbidden -> MUST throw permissionDenied
        adapter.enqueue(
          'GET',
          '/api/tenant/info/t-forbidden',
          (_) => MockDioAdapter.jsonResponse({
            'status': 403,
            'errorCode': 20,
            'message': 'Permission denied',
          }, statusCode: 403),
        );
        await expectLater(
          repo.getTenantInfo('t-forbidden'),
          throwsA(
            isA<TbFailure>().having(
              (f) => f.type,
              'type',
              TbFailureType.permissionDenied,
            ),
          ),
        );

        // 3) POST /api/tenant & DELETE /api/tenant/{id}
        adapter.on('POST', '/api/tenant', (opts) {
          final body = opts.data as Map<String, dynamic>;
          expect(body['title'], 'Updated Tenant');
          return MockDioAdapter.jsonResponse({
            ...body,
            'id': {'entityType': 'TENANT', 'id': 't-1'},
          });
        });
        var deleted = false;
        adapter.on('DELETE', '/api/tenant/t-1', (_) {
          deleted = true;
          return MockDioAdapter.emptyResponse();
        });

        final saved = await repo.saveTenant(
          info.copyWith(title: 'Updated Tenant'),
        );
        expect(saved.title, 'Updated Tenant');
        await repo.deleteTenant('t-1');
        expect(deleted, isTrue);

        // 4) /api/tenantInfos falls back to /api/tenants on 404; /api/tenants/list falls back per-ID on 404
        adapter.enqueue(
          'GET',
          '/api/tenantInfos',
          (_) => MockDioAdapter.jsonResponse({'status': 404}, statusCode: 404),
        );
        adapter.on(
          'GET',
          '/api/tenants',
          (_) => MockDioAdapter.jsonResponse({
            'data': [
              {
                'id': {'entityType': 'TENANT', 'id': 't-1'},
                'title': 'DemoCloud IoT',
              },
            ],
            'totalPages': 1,
            'totalElements': 1,
            'hasNext': false,
          }),
        );

        final page = await repo.getTenantInfos(const PageQuery());
        expect(page.data.single.title, 'DemoCloud IoT');

        final byIds = await repo.getTenantsByIds(const ['t-1']);
        expect(byIds.single.id, 't-1');
      },
    );

    test(
      'TenantProfile routes support default, info, list, save, setDefault, and delete',
      () async {
        final repo = RestTenantRepository(client: client);

        adapter.on(
          'GET',
          '/api/tenantProfileInfo/default',
          (_) => MockDioAdapter.jsonResponse({
            'id': {'entityType': 'TENANT_PROFILE', 'id': 'tp-1'},
            'name': 'Default',
            'default': true,
          }),
        );
        adapter.on(
          'GET',
          '/api/tenantProfileInfos',
          (_) => MockDioAdapter.jsonResponse({
            'data': [
              {
                'id': {'entityType': 'TENANT_PROFILE', 'id': 'tp-1'},
                'name': 'Default',
                'default': true,
              },
            ],
            'totalPages': 1,
            'totalElements': 1,
            'hasNext': false,
          }),
        );
        adapter.on('POST', '/api/tenantProfile', (opts) {
          final body = opts.data as Map<String, dynamic>;
          return MockDioAdapter.jsonResponse({
            ...body,
            'id': {'entityType': 'TENANT_PROFILE', 'id': 'tp-2'},
          });
        });
        adapter.on(
          'POST',
          '/api/tenantProfile/tp-2/default',
          (_) => MockDioAdapter.jsonResponse({
            'id': {'entityType': 'TENANT_PROFILE', 'id': 'tp-2'},
            'name': 'Enterprise',
            'default': true,
          }),
        );
        var deletedProfile = false;
        adapter.on('DELETE', '/api/tenantProfile/tp-2', (_) {
          deletedProfile = true;
          return MockDioAdapter.emptyResponse();
        });

        final def = await repo.getDefaultTenantProfileInfo();
        expect(def?.name, 'Default');
        expect(def?.isDefault, isTrue);

        final infos = await repo.getTenantProfileInfos(const PageQuery());
        expect(infos.data.single.id, 'tp-1');

        final created = await repo.saveTenantProfile(
          const TbTenantProfileInfo(id: '', name: 'Enterprise'),
        );
        expect(created.id, 'tp-2');

        final promoted = await repo.setDefaultTenantProfile('tp-2');
        expect(promoted.isDefault, isTrue);

        await repo.deleteTenantProfile('tp-2');
        expect(deletedProfile, isTrue);
      },
    );

    test(
      'Tenant users, subscription summary (404-safe on TB 3.3), queues, entityViews, and edges map PE 4.4 & TB 3.3',
      () async {
        final repo = RestTenantRepository(client: client);

        adapter.on(
          'GET',
          '/api/tenant/t-1/users',
          (_) => MockDioAdapter.jsonResponse({
            'data': [
              {
                'id': {'entityType': 'USER', 'id': 'u-1'},
                'email': 'admin@democloud.xyz',
                'authority': 'TENANT_ADMIN',
              },
            ],
            'totalPages': 1,
            'totalElements': 1,
            'hasNext': false,
          }),
        );
        final users = await repo.getTenantUsers('t-1', const PageQuery());
        expect(users.data.single.email, 'admin@democloud.xyz');

        // On TB 3.3, /api/tenant/subscription* returns 404 -> returns null gracefully!
        expect(await repo.getSubscriptionSummary(), isNull);

        // On PE 4.4, /api/tenant/subscription + usage + whiteLabelingAllowed succeed!
        adapter.on(
          'GET',
          '/api/tenant/subscription',
          (_) =>
              MockDioAdapter.jsonResponse({'plan': 'Maker', 'state': 'ACTIVE'}),
        );
        adapter.on(
          'GET',
          '/api/tenant/subscription/usage',
          (_) => MockDioAdapter.jsonResponse({'devices': 10, 'maxDevices': 30}),
        );
        adapter.on(
          'GET',
          '/api/tenant/whiteLabelingAllowed',
          (_) => MockDioAdapter.jsonResponse(true),
        );
        final sub = await repo.getSubscriptionSummary();
        expect(sub?.planName, 'Maker');
        expect(sub?.whiteLabelingAllowed, isTrue);
        expect(sub?.usage['devices'], 10);

        // EntityViews: /api/tenant/entityViewInfos -> falls back to /api/tenant/entityViews on PE 4.4 404;
        // getTenantEntityViewByName: /api/tenant/entityView -> falls back to /api/tenant/entityViews?entityViewName=... on TB 3.3 404!
        adapter.on('GET', '/api/tenant/entityViews', (opts) {
          if (opts.queryParameters.containsKey('entityViewName')) {
            return MockDioAdapter.jsonResponse({
              'id': {'entityType': 'ENTITY_VIEW', 'id': 'ev-1'},
              'name': opts.queryParameters['entityViewName'],
              'type': 'FloodView',
              'entityId': {'entityType': 'DEVICE', 'id': 'dev-1'},
            });
          }
          return MockDioAdapter.jsonResponse({
            'data': [
              {
                'id': {'entityType': 'ENTITY_VIEW', 'id': 'ev-1'},
                'name': 'Public Flood View',
                'type': 'FloodView',
                'entityId': {'entityType': 'DEVICE', 'id': 'dev-1'},
              },
            ],
            'totalPages': 1,
            'totalElements': 1,
            'hasNext': false,
          });
        });

        final views = await repo.getTenantEntityViews(const PageQuery());
        expect(views.data.single.name, 'Public Flood View');
        final viewByName = await repo.getTenantEntityViewByName(
          'Public Flood View',
        );
        expect(viewByName.id, 'ev-1');

        // Edges: /api/tenant/edgeInfos -> /api/tenant/edges; /api/tenant/edge -> /api/tenant/edges?edgeName=...
        adapter.on('GET', '/api/tenant/edges', (opts) {
          if (opts.queryParameters.containsKey('edgeName')) {
            return MockDioAdapter.jsonResponse({
              'id': {'entityType': 'EDGE', 'id': 'edge-1'},
              'name': opts.queryParameters['edgeName'],
              'type': 'GatewayEdge',
            });
          }
          return MockDioAdapter.jsonResponse({
            'data': [
              {
                'id': {'entityType': 'EDGE', 'id': 'edge-1'},
                'name': 'Station Edge 01',
                'type': 'GatewayEdge',
              },
            ],
            'totalPages': 1,
            'totalElements': 1,
            'hasNext': false,
          });
        });

        final edges = await repo.getTenantEdges(const PageQuery());
        expect(edges.data.single.name, 'Station Edge 01');
        final edgeByName = await repo.getTenantEdgeByName('Station Edge 01');
        expect(edgeByName.id, 'edge-1');

        // Queues: /api/tenant/queues?serviceType=TB_RULE_ENGINE
        adapter.on(
          'GET',
          '/api/tenant/queues',
          (opts) => MockDioAdapter.jsonResponse([
            {'name': 'Main', 'topic': 'tb_rule_engine.main'},
          ]),
        );
        final queues = await repo.getTenantQueues(
          serviceType: 'TB_RULE_ENGINE',
        );
        expect(queues.single['name'], 'Main');
      },
    );
  });

  group(
    '/api/tenant/* entity sub-routes on Device, Asset, Customer & Dashboard repos',
    () {
      test(
        'Device, Asset, Customer, and Dashboard /api/tenant/* methods map PE 4.4 & TB 3.3 cleanly',
        () async {
          final devRepo = RestDeviceRepository(client: client);
          final assetRepo = RestAssetRepository(client: client);
          final custRepo = RestCustomerRepository(client: client);
          final dashRepo = RestDashboardRepository(client: client);

          // Device: /api/tenant/devices, /api/tenant/device -> fallback /api/tenant/devices?deviceName=..., POST /api/tenant/{tenantId}/device/{deviceId}
          adapter.on('GET', '/api/tenant/devices', (opts) {
            if (opts.queryParameters.containsKey('deviceName')) {
              return MockDioAdapter.jsonResponse({
                'id': {'entityType': 'DEVICE', 'id': 'd-named'},
                'name': opts.queryParameters['deviceName'],
                'type': 'Bringter Flood',
              });
            }
            return MockDioAdapter.jsonResponse({
              'data': [
                {
                  'id': {'entityType': 'DEVICE', 'id': 'd-1'},
                  'name': 'Bringter_flood_005',
                  'type': 'Bringter Flood',
                },
              ],
              'totalPages': 1,
              'totalElements': 1,
              'hasNext': false,
            });
          });
          adapter.on(
            'POST',
            '/api/tenant/t-2/device/d-1',
            (_) => MockDioAdapter.jsonResponse({
              'id': {'entityType': 'DEVICE', 'id': 'd-1'},
              'tenantId': {'entityType': 'TENANT', 'id': 't-2'},
              'name': 'Bringter_flood_005',
              'type': 'Bringter Flood',
            }),
          );

          expect(
            (await devRepo.getTenantDevices(
              const PageQuery(),
            )).data.single.name,
            'Bringter_flood_005',
          );
          expect(
            (await devRepo.getTenantDeviceByName('SensorX')).id,
            'd-named',
          );
          expect(
            (await devRepo.assignDeviceToTenant('t-2', 'd-1')).tenantId,
            't-2',
          );

          // Asset: /api/tenant/assets, /api/tenant/asset -> fallback /api/tenant/assets?assetName=...
          adapter.on('GET', '/api/tenant/assets', (opts) {
            if (opts.queryParameters.containsKey('assetName')) {
              return MockDioAdapter.jsonResponse({
                'id': {'entityType': 'ASSET', 'id': 'a-named'},
                'name': opts.queryParameters['assetName'],
                'type': 'Building',
              });
            }
            return MockDioAdapter.jsonResponse({
              'data': [
                {
                  'id': {'entityType': 'ASSET', 'id': 'a-1'},
                  'name': 'Station HQ',
                  'type': 'Building',
                },
              ],
              'totalPages': 1,
              'totalElements': 1,
              'hasNext': false,
            });
          });
          expect(
            (await assetRepo.getTenantAssets(
              const PageQuery(),
            )).data.single.name,
            'Station HQ',
          );
          expect((await assetRepo.getTenantAssetByName('HQ')).id, 'a-named');

          // Customer: GET /api/tenant/customers?customerTitle=...
          adapter.on('GET', '/api/tenant/customers', (opts) {
            expect(opts.queryParameters['customerTitle'], 'Acme Corp');
            return MockDioAdapter.jsonResponse({
              'id': {'entityType': 'CUSTOMER', 'id': 'c-1'},
              'title': 'Acme Corp',
            });
          });
          expect(
            (await custRepo.getTenantCustomerByTitle('Acme Corp')).id,
            'c-1',
          );

          // Dashboard: GET /api/tenant/{tenantId}/dashboards & GET/POST /api/tenant/dashboard/home/info
          adapter.on(
            'GET',
            '/api/tenant/t-1/dashboards',
            (_) => MockDioAdapter.jsonResponse({
              'data': [
                {
                  'id': {'entityType': 'DASHBOARD', 'id': 'dash-1'},
                  'title': 'Tenant Flood Overview',
                },
              ],
              'totalPages': 1,
              'totalElements': 1,
              'hasNext': false,
            }),
          );
          adapter.on(
            'GET',
            '/api/tenant/dashboard/home/info',
            (_) => MockDioAdapter.jsonResponse({
              'dashboardId': {'entityType': 'DASHBOARD', 'id': 'dash-1'},
              'hideDashboardToolbar': false,
            }),
          );
          Map<String, dynamic>? postedHome;
          adapter.on('POST', '/api/tenant/dashboard/home/info', (opts) {
            postedHome = opts.data as Map<String, dynamic>;
            return MockDioAdapter.emptyResponse();
          });

          final tDash = await dashRepo.getTenantDashboardsByTenantId(
            't-1',
            const PageQuery(),
          );
          expect(tDash.data.single.title, 'Tenant Flood Overview');

          final homeInfo = await dashRepo.getTenantHomeDashboardInfo();
          expect(homeInfo?.dashboardId, 'dash-1');
          expect(homeInfo?.hideDashboardToolbar, isFalse);

          await dashRepo.setTenantHomeDashboardInfo(
            const TbHomeDashboardInfo(
              dashboardId: 'dash-1',
              hideDashboardToolbar: true,
            ),
          );
          expect(postedHome?['hideDashboardToolbar'], isTrue);
        },
      );

      test('DemoTenantRepository works completely offline', () async {
        final demo = DemoTenantRepository();
        final current = await demo.getTenantInfo('demo-tenant-1');
        expect(current.title, isNotEmpty);

        final updated = await demo.saveTenant(
          current.copyWith(title: 'Demo Smart City'),
        );
        expect(updated.title, 'Demo Smart City');

        final views = await demo.getTenantEntityViews(const PageQuery());
        expect(views.data, isNotEmpty);

        final edges = await demo.getTenantEdges(const PageQuery());
        expect(edges.data, isNotEmpty);
      });
    },
  );
}
