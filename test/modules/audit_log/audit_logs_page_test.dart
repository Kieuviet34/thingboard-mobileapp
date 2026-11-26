import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:thingsboard_democloud_app/config/themes/tb_theme.dart';
import 'package:thingsboard_democloud_app/core/api/controllers/audit_log_controller.dart';
import 'package:thingsboard_democloud_app/core/api/controllers/server_config_controller.dart';
import 'package:thingsboard_democloud_app/core/api/repositories/audit_log_repository.dart';
import 'package:thingsboard_democloud_app/core/models/audit_log_models.dart';
import 'package:thingsboard_democloud_app/core/models/entity_id.dart';
import 'package:thingsboard_democloud_app/core/models/pagination.dart';
import 'package:thingsboard_democloud_app/core/models/tb_failure.dart';
import 'package:thingsboard_democloud_app/modules/audit_log/audit_logs_page.dart';
import 'package:thingsboard_democloud_app/widgets/icons/tb_icons.dart';
import 'package:thingsboard_democloud_app/widgets/tb_empty_state.dart';
import 'package:thingsboard_democloud_app/widgets/tb_list_row.dart';
import 'package:thingsboard_democloud_app/widgets/tb_status_badge.dart';

import '../../helpers/fake_app_preferences.dart';
import '../../helpers/fake_secure_storage.dart';
import '../../helpers/fake_ws_channel.dart';
import '../../helpers/mock_dio_adapter.dart';

class _FakeAuditLogRepo implements AuditLogRepository {
  _FakeAuditLogRepo({this.logs = const [], this.throwFailure});

  List<TbAuditLog> logs;
  TbFailure? throwFailure;

  @override
  Future<PageData<TbAuditLog>> getAuditLogs(
    PageQuery query,
    TbAuditLogQuery filter, {
    CancelToken? cancelToken,
  }) async {
    if (throwFailure != null) throw throwFailure!;

    final search = filter.textSearch?.toLowerCase() ?? '';
    final actions = filter.actionTypes;

    final filtered = logs.where((l) {
      if (actions.isNotEmpty && !actions.contains(l.actionType)) return false;
      if (search.isNotEmpty &&
          !l.entityName.toLowerCase().contains(search) &&
          !l.actionType.toLowerCase().contains(search)) {
        return false;
      }
      return true;
    }).toList();

    return PageData<TbAuditLog>(
      data: filtered,
      totalPages: 1,
      totalElements: filtered.length,
      hasNext: false,
    );
  }
}

final _sampleLogs = [
  const TbAuditLog(
    id: 'log-1',
    entityName: 'Solar Inverter 01',
    entityType: EntityType.device,
    actionType: 'UPDATED',
    isSuccess: true,
    createdTime: 1700000000000,
    userName: 'tenant@thingsboard.org',
    actionData: {'firmware': 'v2.1.0', 'power': 1200},
  ),
  const TbAuditLog(
    id: 'log-2',
    entityName: 'Security Gate Hub',
    entityType: EntityType.asset,
    actionType: 'LOGIN',
    isSuccess: false,
    createdTime: 1700000100000,
    userName: 'admin@tb.io',
    failureDetails: 'Invalid 2FA code provided',
  ),
];

void main() {
  Widget buildApp({
    required AuditLogRepository repo,
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
        auditLogRepositoryProvider.overrideWithValue(repo),
      ],
      child: MediaQuery(
        data: MediaQueryData(
          size: const Size(390, 844),
          textScaler: TextScaler.linear(textScale),
          disableAnimations: disableAnimations,
        ),
        child: MaterialApp(
          theme: theme ?? tbLightTheme(),
          home: const AuditLogsPage(),
        ),
      ),
    );
  }

  group('AuditLogsPage', () {
    testWidgets(
      'renders audit logs timeline with icons, status badge and details',
      (tester) async {
        final repo = _FakeAuditLogRepo(logs: _sampleLogs);
        await tester.pumpWidget(buildApp(repo: repo));
        await tester.pumpAndSettle();

        expect(find.text('Audit Logs'), findsOneWidget);
        expect(find.text('Solar Inverter 01'), findsOneWidget);
        expect(find.text('Security Gate Hub'), findsOneWidget);
        expect(find.text('UPDATED'), findsWidgets);
        expect(find.text('LOGIN'), findsWidgets);
        expect(find.byType(TbStatusBadge), findsWidgets);
        expect(find.byType(TbIcon), findsWidgets);
      },
    );

    testWidgets('rows use TbListRow with action and user meta', (tester) async {
      final repo = _FakeAuditLogRepo(logs: _sampleLogs);
      await tester.pumpWidget(buildApp(repo: repo));
      await tester.pumpAndSettle();

      final rows = tester
          .widgetList<TbListRow>(find.byType(TbListRow))
          .toList();
      expect(rows, hasLength(2));
      expect(rows[0].title, 'Solar Inverter 01');
      expect(rows[0].meta, startsWith('UPDATED · '));
      expect(rows[0].meta, endsWith(' · tenant@thingsboard.org'));
      expect(rows[1].meta, endsWith(' · admin@tb.io'));

      final ok = tester.widget<TbStatusBadge>(
        find.byKey(const ValueKey('audit-status-log-1')),
      );
      final failed = tester.widget<TbStatusBadge>(
        find.byKey(const ValueKey('audit-status-log-2')),
      );
      expect(ok.label, 'SUCCESS');
      expect(failed.label, 'FAILED');
    });

    testWidgets('filtering by action chip updates the list', (tester) async {
      final repo = _FakeAuditLogRepo(logs: _sampleLogs);
      await tester.pumpWidget(buildApp(repo: repo));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilterChip, 'LOGIN'));
      await tester.pumpAndSettle();

      expect(find.text('Security Gate Hub'), findsOneWidget);
      expect(find.text('Solar Inverter 01'), findsNothing);
    });

    testWidgets('tapping log opens JSON bottom sheet with action details', (
      tester,
    ) async {
      final repo = _FakeAuditLogRepo(logs: _sampleLogs);
      await tester.pumpWidget(buildApp(repo: repo));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Solar Inverter 01'));
      await tester.pumpAndSettle();

      expect(find.text('Audit Log Details'), findsOneWidget);
      expect(find.textContaining('v2.1.0'), findsOneWidget);
      expect(find.textContaining('1200'), findsOneWidget);

      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      expect(find.text('Audit Log Details'), findsNothing);
    });

    testWidgets('empty list renders TbEmptyState', (tester) async {
      final repo = _FakeAuditLogRepo(logs: []);
      await tester.pumpWidget(buildApp(repo: repo));
      await tester.pumpAndSettle();

      expect(find.byType(TbEmptyState), findsOneWidget);
      expect(find.text('No audit logs recorded'), findsOneWidget);
    });

    testWidgets('403 error renders Access Restricted empty state', (
      tester,
    ) async {
      final repo = _FakeAuditLogRepo(
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

    testWidgets('renders in Dark theme at 2.0x text scale without overflow', (
      tester,
    ) async {
      final repo = _FakeAuditLogRepo(logs: _sampleLogs);
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
      expect(find.text('Audit Logs'), findsOneWidget);
      expect(find.text('Solar Inverter 01'), findsOneWidget);
    });
  });
}
