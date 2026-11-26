import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:thingsboard_democloud_app/config/themes/tb_theme.dart';
import 'package:thingsboard_democloud_app/core/api/controllers/alarm_controller.dart';
import 'package:thingsboard_democloud_app/core/api/controllers/server_config_controller.dart';
import 'package:thingsboard_democloud_app/core/api/repositories/alarm_repository.dart';
import 'package:thingsboard_democloud_app/core/models/alarm_models.dart';
import 'package:thingsboard_democloud_app/core/models/entity_id.dart';
import 'package:thingsboard_democloud_app/core/models/pagination.dart';
import 'package:thingsboard_democloud_app/core/models/tb_failure.dart';
import 'package:thingsboard_democloud_app/modules/alarm/alarms_page.dart';
import 'package:thingsboard_democloud_app/widgets/icons/tb_icons.dart';
import 'package:thingsboard_democloud_app/widgets/tb_app_search_bar.dart';
import 'package:thingsboard_democloud_app/widgets/tb_empty_state.dart';
import 'package:thingsboard_democloud_app/widgets/tb_list_row.dart';
import 'package:thingsboard_democloud_app/widgets/tb_shimmer.dart';
import 'package:thingsboard_democloud_app/widgets/tb_status_badge.dart';

import '../../helpers/fake_app_preferences.dart';
import '../../helpers/fake_secure_storage.dart';
import '../../helpers/fake_ws_channel.dart';

class _MockAlarmRepository implements AlarmRepository {
  _MockAlarmRepository({List<TbAlarmInfo>? alarms})
    : items = List<TbAlarmInfo>.from(
        alarms ??
            [
              const TbAlarmInfo(
                id: 'alarm-1',
                type: 'High Temperature',
                severity: AlarmSeverity.critical,
                acknowledged: false,
                cleared: false,
                createdTime: 1700000000000,
                originatorName: 'Office Sensor',
                assigneeName: 'Alice Smith',
              ),
              const TbAlarmInfo(
                id: 'alarm-2',
                type: 'Low Battery',
                severity: AlarmSeverity.warning,
                acknowledged: true,
                cleared: false,
                createdTime: 1700000005000,
                originatorName: 'Hallway Node',
              ),
              const TbAlarmInfo(
                id: 'alarm-3',
                type: 'Connection Timeout',
                severity: AlarmSeverity.minor,
                acknowledged: true,
                cleared: true,
                createdTime: 1700000010000,
                originatorName: 'Main Gateway',
              ),
            ],
      );

  Completer<PageData<TbAlarmInfo>>? completer;
  bool shouldThrow = false;
  final List<TbAlarmInfo> items;
  final List<String> ackCalls = [];
  final List<String> clearCalls = [];
  final List<PageQuery> queries = [];
  final List<TbAlarmFilter> filters = [];

  @override
  Future<PageData<TbAlarmInfo>> getAlarms(
    PageQuery query,
    TbAlarmFilter filter, {
    CancelToken? cancelToken,
  }) async {
    queries.add(query);
    filters.add(filter);
    if (completer != null) return completer!.future;
    if (shouldThrow) {
      throw const TbFailure(
        type: TbFailureType.networkUnavailable,
        message: 'Network error occurred',
      );
    }
    final filtered = items.where((a) {
      if (filter.textSearch != null && filter.textSearch!.isNotEmpty) {
        final q = filter.textSearch!.toLowerCase();
        if (!a.type.toLowerCase().contains(q) &&
            !a.originatorName.toLowerCase().contains(q)) {
          return false;
        }
      }
      if (filter.severityList.isNotEmpty &&
          !filter.severityList.contains(a.severity)) {
        return false;
      }
      if (filter.statusList.isNotEmpty) {
        var match = false;
        for (final st in filter.statusList) {
          if (st == AlarmSearchStatus.active && !a.cleared) match = true;
          if (st == AlarmSearchStatus.cleared && a.cleared) match = true;
          if (st == AlarmSearchStatus.ack && a.acknowledged) match = true;
          if (st == AlarmSearchStatus.unack && !a.acknowledged) match = true;
        }
        if (!match) return false;
      }
      return true;
    }).toList();

    final start = query.page * query.pageSize;
    if (start >= filtered.length) {
      return PageData<TbAlarmInfo>(
        data: const [],
        totalPages: (filtered.length / query.pageSize).ceil(),
        totalElements: filtered.length,
        hasNext: false,
      );
    }
    final end = (start + query.pageSize).clamp(0, filtered.length);
    return PageData<TbAlarmInfo>(
      data: filtered.sublist(start, end),
      totalPages: (filtered.length / query.pageSize).ceil(),
      totalElements: filtered.length,
      hasNext: end < filtered.length,
    );
  }

  @override
  Future<TbAlarmInfo> getAlarmInfo(String id) async {
    return items.firstWhere((a) => a.id == id);
  }

  @override
  Future<TbAlarmInfo> ackAlarm(String id) async {
    ackCalls.add(id);
    final idx = items.indexWhere((a) => a.id == id);
    if (idx != -1) {
      items[idx] = items[idx].copyWith(acknowledged: true);
      return items[idx];
    }
    throw const TbFailure(
      type: TbFailureType.notFound,
      message: 'Alarm not found',
    );
  }

  @override
  Future<TbAlarmInfo> clearAlarm(String id) async {
    clearCalls.add(id);
    final idx = items.indexWhere((a) => a.id == id);
    if (idx != -1) {
      items[idx] = items[idx].copyWith(cleared: true);
      return items[idx];
    }
    throw const TbFailure(
      type: TbFailureType.notFound,
      message: 'Alarm not found',
    );
  }

  @override
  Future<TbAlarmInfo> assignAlarm(String id, String assigneeId) async {
    final idx = items.indexWhere((a) => a.id == id);
    items[idx] = items[idx].copyWith(
      assigneeId: assigneeId,
      assigneeName: 'Assigned User',
    );
    return items[idx];
  }

  @override
  Future<TbAlarmInfo> unassignAlarm(String id) async {
    final idx = items.indexWhere((a) => a.id == id);
    items[idx] = items[idx].copyWith(clearAssignee: true);
    return items[idx];
  }

  @override
  Future<PageData<TbAlarmComment>> getComments(
    String alarmId,
    PageQuery query,
  ) async {
    return const PageData(
      data: [],
      totalPages: 0,
      totalElements: 0,
      hasNext: false,
    );
  }

  @override
  Future<TbAlarmComment> addComment(String alarmId, String text) async {
    return TbAlarmComment(
      id: 'c-new',
      alarmId: alarmId,
      text: text,
      createdTime: DateTime.now().millisecondsSinceEpoch,
    );
  }

  @override
  Future<PageData<TbUserEmailInfo>> getAssignees(
    String alarmId,
    PageQuery query,
  ) async {
    return const PageData(
      data: [],
      totalPages: 0,
      totalElements: 0,
      hasNext: false,
    );
  }
}

void main() {
  late FakeAppPreferences prefs;
  late FakeSecureStorage storage;
  late _MockAlarmRepository repo;

  setUp(() {
    prefs = FakeAppPreferences();
    storage = FakeSecureStorage();
    repo = _MockAlarmRepository();
  });

  List<Override> buildOverrides() => [
    tbAppPreferencesProvider.overrideWithValue(prefs),
    tbStorageProvider.overrideWithValue(storage),
    wsChannelFactoryProvider.overrideWithValue((_) => FakeWebSocketChannel()),
    alarmRepositoryProvider.overrideWithValue(repo),
  ];

  Widget buildTestWidget(
    WidgetTester tester, {
    bool searchMode = false,
    EntityId? originatorId,
    ThemeData? theme,
    double textScale = 1.0,
    bool disableAnimations = false,
  }) {
    final size = tester.view.physicalSize.width > 0
        ? Size(
            tester.view.physicalSize.width / tester.view.devicePixelRatio,
            tester.view.physicalSize.height / tester.view.devicePixelRatio,
          )
        : const Size(800, 600);
    return ProviderScope(
      overrides: buildOverrides(),
      child: MediaQuery(
        data: MediaQueryData(
          size: size,
          textScaler: TextScaler.linear(textScale),
          disableAnimations: disableAnimations,
        ),
        child: MaterialApp(
          theme: theme ?? tbLightTheme(),
          home: AlarmsPage(searchMode: searchMode, originatorId: originatorId),
        ),
      ),
    );
  }

  group('AlarmsPage Widget Tests', () {
    testWidgets('renders loading shimmer on initial build', (
      WidgetTester tester,
    ) async {
      repo.completer = Completer<PageData<TbAlarmInfo>>();

      await tester.pumpWidget(buildTestWidget(tester));
      await tester.pump();

      expect(find.byType(TbShimmerList), findsOneWidget);
    });

    testWidgets('renders error state and retries successfully', (
      WidgetTester tester,
    ) async {
      repo.shouldThrow = true;

      await tester.pumpWidget(buildTestWidget(tester));
      await tester.pumpAndSettle();

      expect(find.byType(TbEmptyState), findsOneWidget);
      expect(find.text('Failed to load alarms'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);

      repo.shouldThrow = false;
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();

      expect(find.text('High Temperature'), findsOneWidget);
    });

    testWidgets('renders empty state when no alarms exist', (
      WidgetTester tester,
    ) async {
      repo.items.clear();

      await tester.pumpWidget(buildTestWidget(tester));
      await tester.pumpAndSettle();

      expect(find.byType(TbEmptyState), findsOneWidget);
      expect(find.text('No alarms'), findsOneWidget);
      expect(find.text('All systems nominal'), findsOneWidget);
    });

    testWidgets('renders alarm list with M3 status badges and severity glyphs', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(buildTestWidget(tester));
      await tester.pumpAndSettle();

      expect(find.text('High Temperature'), findsOneWidget);
      expect(find.text('Low Battery'), findsOneWidget);
      expect(find.text('Connection Timeout'), findsOneWidget);
      expect(find.byType(TbStatusBadge), findsWidgets);
      expect(find.byType(TbIcon), findsWidgets);
      expect(find.text('Alice Smith'), findsNothing); // Initials avatar used
      // Row meta is "originator · relative time" (ack state shown by the Ack action).
      expect(
        find.textContaining(RegExp(r'^Office Sensor · (now|\d+[mhd] ago)$')),
        findsOneWidget,
      );
    });

    testWidgets('rows are TbListRow with type title and originator meta', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(buildTestWidget(tester));
      await tester.pumpAndSettle();

      expect(find.byType(TbListRow), findsNWidgets(3));
      final firstRow = find.widgetWithText(TbListRow, 'High Temperature');
      expect(firstRow, findsOneWidget);
      final row = tester.widget<TbListRow>(firstRow);
      expect(row.title, 'High Temperature');
      expect(row.meta, startsWith('Office Sensor · '));
      expect(row.meta, endsWith('ago'));
    });

    testWidgets('360dp row with assignee and both actions does not overflow', (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(buildTestWidget(tester));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      for (final key in const ['quick-ack-alarm-1', 'quick-clear-alarm-1']) {
        final f = find.byKey(Key(key));
        expect(f, findsOneWidget);
        expect(f.hitTestable(), findsOneWidget);
      }
    });

    testWidgets('filters alarms by severity and status chips', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(buildTestWidget(tester));
      await tester.pumpAndSettle();

      // Ensure critical severity chip is visible in the scrollable row
      final chipFinder = find.byKey(const Key('alarm-severity-chip-CRITICAL'));
      await tester.ensureVisible(chipFinder);
      await tester.tap(chipFinder);
      await tester.pumpAndSettle();

      expect(find.text('High Temperature'), findsOneWidget);
      expect(find.text('Low Battery'), findsNothing);
      expect(find.text('Connection Timeout'), findsNothing);

      // Tap Reset button to clear filters
      await tester.ensureVisible(
        find.byKey(const Key('alarm-clear-filters-chip')),
      );
      await tester.tap(find.byKey(const Key('alarm-clear-filters-chip')));
      await tester.pumpAndSettle();

      expect(find.text('High Temperature'), findsOneWidget);
      expect(find.text('Low Battery'), findsOneWidget);
      expect(find.text('Connection Timeout'), findsOneWidget);
    });

    testWidgets('toggles search bar and filters alarms by text', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(buildTestWidget(tester));
      await tester.pumpAndSettle();

      expect(find.byType(TbAppSearchBar), findsNothing);

      await tester.tap(find.byKey(const Key('alarms-search-toggle-button')));
      await tester.pumpAndSettle();

      expect(find.byType(TbAppSearchBar), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'Battery');
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();

      expect(find.text('Low Battery'), findsOneWidget);
      expect(find.text('High Temperature'), findsNothing);

      await tester.tap(find.byKey(const Key('alarms-search-close-button')));
      await tester.pumpAndSettle();

      expect(find.byType(TbAppSearchBar), findsNothing);
      expect(find.text('High Temperature'), findsOneWidget);
    });

    testWidgets(
      'quick ack and clear perform optimistic mutations and show snackbar',
      (WidgetTester tester) async {
        await tester.pumpWidget(buildTestWidget(tester));
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('quick-ack-alarm-1')), findsOneWidget);
        await tester.tap(find.byKey(const Key('quick-ack-alarm-1')));
        await tester.pumpAndSettle();

        expect(repo.ackCalls, contains('alarm-1'));
        expect(find.text('Alarm acknowledged'), findsOneWidget);

        expect(find.byKey(const Key('quick-clear-alarm-1')), findsOneWidget);
        await tester.tap(find.byKey(const Key('quick-clear-alarm-1')));
        await tester.pumpAndSettle();

        expect(repo.clearCalls, contains('alarm-1'));
        expect(find.text('Alarm cleared'), findsOneWidget);
      },
    );

    testWidgets('quick action touch targets meet >= 48dp minimum', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(buildTestWidget(tester));
      await tester.pumpAndSettle();

      final ackFinder = find.byKey(const Key('quick-ack-alarm-1'));
      final ackSize = tester.getSize(ackFinder);
      expect(ackSize.height, greaterThanOrEqualTo(48.0));

      final clearFinder = find.byKey(const Key('quick-clear-alarm-1'));
      final clearSize = tester.getSize(clearFinder);
      expect(clearSize.height, greaterThanOrEqualTo(48.0));
    });

    testWidgets('supports adaptive 2-pane layout on wide screens (>=840dp)', (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = const Size(1024, 768);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(buildTestWidget(tester));
      await tester.pumpAndSettle();

      // Master list and details pane both visible
      expect(find.byType(VerticalDivider), findsOneWidget);
      expect(find.text('High Temperature'), findsWidgets);
      expect(find.text('Timeline & details'), findsOneWidget);
    });

    testWidgets(
      'renders cleanly in dark theme and 2.0x text scale with reduced motion',
      (WidgetTester tester) async {
        await tester.pumpWidget(
          buildTestWidget(
            tester,
            theme: tbDarkTheme(),
            textScale: 2.0,
            disableAnimations: true,
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('High Temperature'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  });
}
