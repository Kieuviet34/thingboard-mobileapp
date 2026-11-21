import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:thingsboard_democloud_app/core/api/controllers/audit_log_controller.dart';
import 'package:thingsboard_democloud_app/core/api/controllers/auth_controller.dart';
import 'package:thingsboard_democloud_app/core/api/controllers/server_config_controller.dart';
import 'package:thingsboard_democloud_app/core/models/audit_log_models.dart';
import 'package:thingsboard_democloud_app/core/models/entity_id.dart';
import 'package:thingsboard_democloud_app/core/models/tb_failure.dart';

import '../../../helpers/fake_app_preferences.dart';
import '../../../helpers/fake_secure_storage.dart';
import '../../../helpers/fake_ws_channel.dart';
import '../../../helpers/mock_dio_adapter.dart';
import '../../../helpers/openapi_contract.dart';
import '../../../helpers/test_container.dart';

const _tenantPath = '/api/audit/logs';
const _tenantQuery = TbAuditLogQuery();

Map<String, dynamic> _logJson(
  String id, {
  String entityName = 'Thermostat-Floor-1',
  String actionType = 'ATTRIBUTES_UPDATED',
}) {
  return {
    'id': {'id': id},
    'entityId': {'entityType': 'DEVICE', 'id': 'dev-1'},
    'entityName': entityName,
    'actionType': actionType,
    'actionStatus': 'SUCCESS',
    'createdTime': 1700000000000,
    'userName': 'user@example.com',
    'actionData': <String, dynamic>{},
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

  group('AuditLogsNotifier (live HTTP)', () {
    test('initial load maps the first page into data state', () async {
      adapter.on(
        'GET',
        _tenantPath,
        (_) => MockDioAdapter.jsonResponse(
          _pageJson(
            [_logJson('log-a'), _logJson('log-b', actionType: 'RPC_CALL')],
            hasNext: false,
            totalElements: 2,
          ),
        ),
      );
      container.listen(auditLogsListProvider(_tenantQuery), (_, _) {});

      final loaded = await container.read(
        auditLogsListProvider(_tenantQuery).future,
      );

      expect(loaded.items.map((l) => l.id), ['log-a', 'log-b']);
      expect(loaded.items.last.actionType, 'RPC_CALL');
      expect(loaded.page, 0);
      expect(loaded.hasNext, isFalse);
      expect(loaded.totalElements, 2);

      final request = adapter.capturedRequests.single;
      expect(request.queryParameters['page'], 0);
      expect(request.queryParameters['pageSize'], 20);
      expect(request.queryParameters['sortProperty'], 'createdTime');
      expect(request.queryParameters['sortOrder'], 'DESC');
      contract.expectAllConform(adapter);
    });

    test('empty response yields an empty data state, not an error', () async {
      adapter.on(
        'GET',
        _tenantPath,
        (_) => MockDioAdapter.jsonResponse(
          _pageJson(const [], hasNext: false, totalElements: 0),
        ),
      );
      container.listen(auditLogsListProvider(_tenantQuery), (_, _) {});

      final loaded = await container.read(
        auditLogsListProvider(_tenantQuery).future,
      );

      expect(loaded.items, isEmpty);
      expect(loaded.hasNext, isFalse);
      expect(loaded.totalElements, 0);
      expect(
        container.read(auditLogsListProvider(_tenantQuery)).hasError,
        isFalse,
      );
    });

    test('HTTP 403 surfaces a TbFailure and refresh recovers', () async {
      adapter.enqueue(
        'GET',
        _tenantPath,
        (_) => MockDioAdapter.jsonResponse({
          'status': 403,
          'errorCode': 20,
          'message': 'Forbidden',
        }, statusCode: 403),
      );
      adapter.on(
        'GET',
        _tenantPath,
        (_) => MockDioAdapter.jsonResponse(
          _pageJson([_logJson('log-ok')], hasNext: false, totalElements: 1),
        ),
      );
      container.listen(auditLogsListProvider(_tenantQuery), (_, _) {});

      await expectLater(
        container.read(auditLogsListProvider(_tenantQuery).future),
        throwsA(isA<TbFailure>()),
      );
      final failed = container.read(auditLogsListProvider(_tenantQuery));
      expect(failed.hasError, isTrue);
      final failure = failed.error! as TbFailure;
      expect(failure.type, TbFailureType.permissionDenied);
      expect(failure.statusCode, 403);

      await container
          .read(auditLogsListProvider(_tenantQuery).notifier)
          .refresh();
      final recovered = container.read(auditLogsListProvider(_tenantQuery));
      expect(recovered.hasError, isFalse);
      expect(recovered.requireValue.items.single.id, 'log-ok');
      contract.expectAllConform(adapter);
    });

    test(
      'loadNextPage appends pages and stops once hasNext is false',
      () async {
        adapter.on('GET', _tenantPath, (opts) {
          final page = opts.queryParameters['page'] as int;
          return MockDioAdapter.jsonResponse(
            page == 0
                ? _pageJson(
                    [_logJson('p0-a'), _logJson('p0-b')],
                    hasNext: true,
                    totalElements: 3,
                  )
                : _pageJson(
                    [_logJson('p1-a')],
                    hasNext: false,
                    totalElements: 3,
                  ),
          );
        });
        container.listen(auditLogsListProvider(_tenantQuery), (_, _) {});
        await container.read(auditLogsListProvider(_tenantQuery).future);
        final notifier = container.read(
          auditLogsListProvider(_tenantQuery).notifier,
        );

        await notifier.loadNextPage();
        final appended = container
            .read(auditLogsListProvider(_tenantQuery))
            .requireValue;
        expect(appended.items.map((l) => l.id), ['p0-a', 'p0-b', 'p1-a']);
        expect(appended.page, 1);
        expect(appended.hasNext, isFalse);
        expect(appended.isLoadingMore, isFalse);
        expect(adapter.capturedRequests.last.queryParameters['page'], 1);

        final requestsBefore = adapter.capturedRequests.length;
        await notifier.loadNextPage();
        expect(adapter.capturedRequests.length, requestsBefore);
        expect(
          container
              .read(auditLogsListProvider(_tenantQuery))
              .requireValue
              .items,
          hasLength(3),
        );
        contract.expectAllConform(adapter);
      },
    );

    test(
      'loadNextPage never starts a second page request while one is in flight',
      () async {
        final gate = Completer<void>();
        adapter.on('GET', _tenantPath, (opts) async {
          final page = opts.queryParameters['page'] as int;
          if (page == 0) {
            return MockDioAdapter.jsonResponse(
              _pageJson([_logJson('p0-a')], hasNext: true, totalElements: 2),
            );
          }
          await gate.future;
          return MockDioAdapter.jsonResponse(
            _pageJson([_logJson('p1-a')], hasNext: false, totalElements: 2),
          );
        });
        container.listen(auditLogsListProvider(_tenantQuery), (_, _) {});
        await container.read(auditLogsListProvider(_tenantQuery).future);
        final notifier = container.read(
          auditLogsListProvider(_tenantQuery).notifier,
        );

        final firstLoad = notifier.loadNextPage();
        await Future<void>.delayed(const Duration(milliseconds: 10));
        expect(
          container
              .read(auditLogsListProvider(_tenantQuery))
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
            .read(auditLogsListProvider(_tenantQuery))
            .requireValue;
        expect(done.items.map((l) => l.id), ['p0-a', 'p1-a']);
        expect(done.isLoadingMore, isFalse);
        expect(done.hasNext, isFalse);
      },
    );

    test(
      'a failed next-page request keeps loaded items and can be retried',
      () async {
        adapter.on('GET', _tenantPath, (opts) {
          final page = opts.queryParameters['page'] as int;
          return MockDioAdapter.jsonResponse(
            page == 0
                ? _pageJson([_logJson('p0-a')], hasNext: true, totalElements: 2)
                : _pageJson(
                    [_logJson('p1-a')],
                    hasNext: false,
                    totalElements: 2,
                  ),
          );
        });
        container.listen(auditLogsListProvider(_tenantQuery), (_, _) {});
        await container.read(auditLogsListProvider(_tenantQuery).future);
        final notifier = container.read(
          auditLogsListProvider(_tenantQuery).notifier,
        );

        adapter.enqueue(
          'GET',
          _tenantPath,
          (_) => MockDioAdapter.jsonResponse({
            'status': 500,
            'message': 'Internal error',
          }, statusCode: 500),
        );
        await notifier.loadNextPage();

        var state = container
            .read(auditLogsListProvider(_tenantQuery))
            .requireValue;
        expect(state.items.map((l) => l.id), ['p0-a']);
        expect(state.isLoadingMore, isFalse);
        expect(state.hasNext, isTrue);
        expect(state.loadMoreError?.type, TbFailureType.serverError);
        expect(state.loadMoreError?.statusCode, 500);

        await notifier.loadNextPage();
        state = container
            .read(auditLogsListProvider(_tenantQuery))
            .requireValue;
        expect(state.items.map((l) => l.id), ['p0-a', 'p1-a']);
        expect(state.loadMoreError, isNull);
        expect(state.hasNext, isFalse);
        contract.expectAllConform(adapter);
      },
    );

    test(
      'an older slower next-page response is discarded after refresh',
      () async {
        final gate = Completer<void>();
        adapter.on('GET', _tenantPath, (opts) async {
          final page = opts.queryParameters['page'] as int;
          if (page == 0) {
            return MockDioAdapter.jsonResponse(
              _pageJson([_logJson('p0-a')], hasNext: true, totalElements: 2),
            );
          }
          await gate.future;
          return MockDioAdapter.jsonResponse(
            _pageJson([_logJson('stale-p1')], hasNext: false, totalElements: 2),
          );
        });
        container.listen(auditLogsListProvider(_tenantQuery), (_, _) {});
        await container.read(auditLogsListProvider(_tenantQuery).future);
        final notifier = container.read(
          auditLogsListProvider(_tenantQuery).notifier,
        );

        final staleLoadMore = notifier.loadNextPage();
        await Future<void>.delayed(const Duration(milliseconds: 10));

        adapter.enqueue(
          'GET',
          _tenantPath,
          (_) => MockDioAdapter.jsonResponse(
            _pageJson([_logJson('fresh-p0')], hasNext: false, totalElements: 1),
          ),
        );
        await notifier.refresh();
        gate.complete();
        await staleLoadMore;

        final state = container.read(auditLogsListProvider(_tenantQuery));
        expect(state.error, isNull);
        expect(state.requireValue.items.map((l) => l.id), ['fresh-p0']);
        expect(state.requireValue.page, 0);
        expect(state.requireValue.hasNext, isFalse);
      },
    );

    test(
      'an older slower refresh never overwrites a newer refresh result',
      () async {
        adapter.on(
          'GET',
          _tenantPath,
          (_) => MockDioAdapter.jsonResponse(
            _pageJson(
              [_logJson('initial-a')],
              hasNext: false,
              totalElements: 1,
            ),
          ),
        );
        container.listen(auditLogsListProvider(_tenantQuery), (_, _) {});
        await container.read(auditLogsListProvider(_tenantQuery).future);
        final notifier = container.read(
          auditLogsListProvider(_tenantQuery).notifier,
        );

        final gate = Completer<void>();
        adapter.enqueue('GET', _tenantPath, (_) async {
          await gate.future;
          return MockDioAdapter.jsonResponse(
            _pageJson([_logJson('stale-a')], hasNext: false, totalElements: 1),
          );
        });
        adapter.enqueue(
          'GET',
          _tenantPath,
          (_) => MockDioAdapter.jsonResponse(
            _pageJson([_logJson('fresh-a')], hasNext: false, totalElements: 1),
          ),
        );

        final staleRefresh = notifier.refresh();
        await Future<void>.delayed(const Duration(milliseconds: 10));
        await notifier.refresh();
        gate.complete();
        await staleRefresh;

        final state = container.read(auditLogsListProvider(_tenantQuery));
        expect(
          state.error,
          isNull,
          reason:
              'stale refresh must not replace the newer result with an error',
        );
        expect(state.value?.items.map((l) => l.id), ['fresh-a']);
      },
    );

    test('a different search query loads its own results', () async {
      const alpha = TbAuditLogQuery(textSearch: 'alpha');
      const beta = TbAuditLogQuery(textSearch: 'beta');
      adapter.on('GET', _tenantPath, (opts) {
        final search = opts.queryParameters['textSearch'] as String;
        return MockDioAdapter.jsonResponse(
          _pageJson(
            [_logJson('$search-1', entityName: search)],
            hasNext: false,
            totalElements: 1,
          ),
        );
      });
      container.listen(auditLogsListProvider(alpha), (_, _) {});
      container.listen(auditLogsListProvider(beta), (_, _) {});

      final alphaLoaded = await container.read(
        auditLogsListProvider(alpha).future,
      );
      final betaLoaded = await container.read(
        auditLogsListProvider(beta).future,
      );

      expect(alphaLoaded.items.map((l) => l.id), ['alpha-1']);
      expect(betaLoaded.items.map((l) => l.id), ['beta-1']);
      expect(
        adapter.capturedRequests.map((r) => r.queryParameters['textSearch']),
        ['alpha', 'beta'],
      );
      contract.expectAllConform(adapter);
    });

    test(
      'a late response for a previous search never overwrites the newer search',
      () async {
        const alpha = TbAuditLogQuery(textSearch: 'alpha');
        const beta = TbAuditLogQuery(textSearch: 'beta');
        final alphaGate = Completer<void>();
        adapter.on('GET', _tenantPath, (opts) async {
          final search = opts.queryParameters['textSearch'] as String;
          if (search == 'alpha') await alphaGate.future;
          return MockDioAdapter.jsonResponse(
            _pageJson(
              [_logJson('$search-1', entityName: search)],
              hasNext: false,
              totalElements: 1,
            ),
          );
        });
        container.listen(auditLogsListProvider(alpha), (_, _) {});
        container.listen(auditLogsListProvider(beta), (_, _) {});

        final betaLoaded = await container.read(
          auditLogsListProvider(beta).future,
        );
        alphaGate.complete();
        await container.read(auditLogsListProvider(alpha).future);

        expect(betaLoaded.items.map((l) => l.id), ['beta-1']);
        expect(
          container
              .read(auditLogsListProvider(beta))
              .requireValue
              .items
              .map((l) => l.id),
          ['beta-1'],
        );
      },
    );

    test(
      'entity scope builds the entity path and forwards action/time filters',
      () async {
        const deviceLogs = TbAuditLogQuery(
          scope: AuditLogScope.entity,
          entityType: EntityType.device,
          targetId: 'dev-1',
          actionTypes: ['RPC_CALL', 'UPDATED'],
          startTime: 1000,
          endTime: 2000,
        );
        adapter.on(
          'GET',
          '/api/audit/logs/entity/DEVICE/dev-1',
          (_) => MockDioAdapter.jsonResponse(
            _pageJson([_logJson('dev-log')], hasNext: false, totalElements: 1),
          ),
        );
        container.listen(auditLogsListProvider(deviceLogs), (_, _) {});

        final loaded = await container.read(
          auditLogsListProvider(deviceLogs).future,
        );

        expect(loaded.items.map((l) => l.id), ['dev-log']);
        final request = adapter.capturedRequests.single;
        expect(request.queryParameters['actionTypes'], 'RPC_CALL,UPDATED');
        expect(request.queryParameters['startTime'], 1000);
        expect(request.queryParameters['endTime'], 2000);
        contract.expectAllConform(adapter);
      },
    );
  });

  group('AuditLogsNotifier (demo mode)', () {
    test(
      'seeded logs are served offline with local search and action filters',
      () async {
        await container.read(authProvider.notifier).loginDemo();
        const pumpQuery = TbAuditLogQuery(textSearch: 'pump');
        const ackQuery = TbAuditLogQuery(actionTypes: ['ALARM_ACK']);
        container.listen(auditLogsListProvider(_tenantQuery), (_, _) {});
        container.listen(auditLogsListProvider(pumpQuery), (_, _) {});
        container.listen(auditLogsListProvider(ackQuery), (_, _) {});

        final all = await container.read(
          auditLogsListProvider(_tenantQuery).future,
        );
        expect(all.items.map((l) => l.id), [
          'log-1',
          'log-2',
          'log-3',
          'log-4',
        ]);
        expect(all.items.every((l) => l.userName == 'John Doe'), isTrue);
        expect(all.hasNext, isFalse);
        expect(adapter.capturedRequests, isEmpty);

        final pump = await container.read(
          auditLogsListProvider(pumpQuery).future,
        );
        expect(pump.items.map((l) => l.id), ['log-3']);
        expect(pump.items.single.isSuccess, isFalse);

        final acks = await container.read(
          auditLogsListProvider(ackQuery).future,
        );
        expect(acks.items.map((l) => l.id), ['log-2']);
      },
    );

    test('demo mode has no next page, so loadNextPage is a no-op', () async {
      await container.read(authProvider.notifier).loginDemo();
      container.listen(auditLogsListProvider(_tenantQuery), (_, _) {});
      await container.read(auditLogsListProvider(_tenantQuery).future);

      await container
          .read(auditLogsListProvider(_tenantQuery).notifier)
          .loadNextPage();

      final state = container
          .read(auditLogsListProvider(_tenantQuery))
          .requireValue;
      expect(state.items, hasLength(4));
      expect(state.page, 0);
      expect(state.isLoadingMore, isFalse);
      expect(state.loadMoreError, isNull);
    });
  });
}
