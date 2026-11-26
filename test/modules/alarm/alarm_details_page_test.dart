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
import 'package:thingsboard_democloud_app/modules/alarm/alarm_details_page.dart';
import 'package:thingsboard_democloud_app/widgets/tb_empty_state.dart';
import 'package:thingsboard_democloud_app/widgets/tb_shimmer.dart';
import 'package:thingsboard_democloud_app/widgets/tb_section_card.dart';
import 'package:thingsboard_democloud_app/widgets/tb_status_badge.dart';

import '../../helpers/fake_app_preferences.dart';
import '../../helpers/fake_secure_storage.dart';
import '../../helpers/fake_ws_channel.dart';

class _ControlledAlarmDetailsRepo implements AlarmRepository {
  _ControlledAlarmDetailsRepo()
    : alarm = const TbAlarmInfo(
        id: 'alarm-detail-1',
        type: 'High Pressure Alert',
        severity: AlarmSeverity.major,
        acknowledged: false,
        cleared: false,
        createdTime: 1700000000000,
        startTs: 1700000000000,
        endTs: 1700000060000,
        originatorName: 'Pump Station 1',
        originator: EntityId(entityType: EntityType.device, id: 'dev-pump-1'),
        assigneeName: 'John Doe',
        assigneeEmail: 'john@example.com',
        assigneeId: 'user-john-1',
        dashboardId: 'dash-1',
        details: {'threshold': '120 bar', 'current': '145 bar'},
      ),
      comments = [
        const TbAlarmComment(
          id: 'comm-1',
          alarmId: 'alarm-detail-1',
          text: 'Automatic notification sent',
          createdTime: 1700000010000,
          type: AlarmCommentType.system,
        ),
        const TbAlarmComment(
          id: 'comm-2',
          alarmId: 'alarm-detail-1',
          text: 'Investigating valve leak',
          firstName: 'John',
          lastName: 'Doe',
          createdTime: 1700000020000,
          type: AlarmCommentType.other,
        ),
      ],
      assignees = [
        const TbUserEmailInfo(
          id: 'user-1',
          email: 'alice@example.com',
          firstName: 'Alice',
          lastName: 'Smith',
        ),
        const TbUserEmailInfo(
          id: 'user-2',
          email: 'bob@example.com',
          firstName: 'Bob',
          lastName: 'Jones',
        ),
      ];

  Completer<TbAlarmInfo>? completer;
  bool shouldThrow = false;
  TbAlarmInfo alarm;
  final List<TbAlarmComment> comments;
  final List<TbUserEmailInfo> assignees;
  final List<String> addedComments = [];
  bool ackCalled = false;
  bool clearCalled = false;
  String? assignedId;
  bool unassignCalled = false;

  @override
  Future<PageData<TbAlarmInfo>> getAlarms(
    PageQuery query,
    TbAlarmFilter filter, {
    CancelToken? cancelToken,
  }) async {
    return PageData(
      data: [alarm],
      totalPages: 1,
      totalElements: 1,
      hasNext: false,
    );
  }

  @override
  Future<TbAlarmInfo> getAlarmInfo(String id) async {
    if (completer != null) return completer!.future;
    if (shouldThrow) {
      throw const TbFailure(
        type: TbFailureType.networkUnavailable,
        message: 'Could not reach server',
      );
    }
    return alarm;
  }

  @override
  Future<TbAlarmInfo> ackAlarm(String id) async {
    ackCalled = true;
    alarm = alarm.copyWith(acknowledged: true, ackTs: 1700000030000);
    return alarm;
  }

  @override
  Future<TbAlarmInfo> clearAlarm(String id) async {
    clearCalled = true;
    alarm = alarm.copyWith(cleared: true, clearTs: 1700000040000);
    return alarm;
  }

  @override
  Future<TbAlarmInfo> assignAlarm(String id, String assigneeId) async {
    assignedId = assigneeId;
    final user = assignees.firstWhere((u) => u.id == assigneeId);
    alarm = alarm.copyWith(
      assigneeId: user.id,
      assigneeName: user.displayName,
      assigneeEmail: user.email,
    );
    return alarm;
  }

  @override
  Future<TbAlarmInfo> unassignAlarm(String id) async {
    unassignCalled = true;
    alarm = alarm.copyWith(clearAssignee: true);
    return alarm;
  }

  @override
  Future<PageData<TbAlarmComment>> getComments(
    String alarmId,
    PageQuery query,
  ) async {
    return PageData(
      data: List.unmodifiable(comments),
      totalPages: 1,
      totalElements: comments.length,
      hasNext: false,
    );
  }

  @override
  Future<TbAlarmComment> addComment(String alarmId, String text) async {
    addedComments.add(text);
    final comment = TbAlarmComment(
      id: 'comm-${comments.length + 1}',
      alarmId: alarmId,
      text: text,
      firstName: 'You',
      createdTime: DateTime.now().millisecondsSinceEpoch,
    );
    comments.add(comment);
    return comment;
  }

  @override
  Future<PageData<TbUserEmailInfo>> getAssignees(
    String alarmId,
    PageQuery query,
  ) async {
    final search = query.textSearch?.trim().toLowerCase() ?? '';
    final filtered = assignees.where((u) {
      return search.isEmpty ||
          u.displayName.toLowerCase().contains(search) ||
          u.email.toLowerCase().contains(search);
    }).toList();
    return PageData(
      data: filtered,
      totalPages: 1,
      totalElements: filtered.length,
      hasNext: false,
    );
  }
}

void main() {
  late FakeAppPreferences prefs;
  late FakeSecureStorage storage;
  late _ControlledAlarmDetailsRepo repo;

  setUp(() {
    prefs = FakeAppPreferences();
    storage = FakeSecureStorage();
    repo = _ControlledAlarmDetailsRepo();
  });

  List<Override> buildOverrides() => [
    tbAppPreferencesProvider.overrideWithValue(prefs),
    tbStorageProvider.overrideWithValue(storage),
    wsChannelFactoryProvider.overrideWithValue((_) => FakeWebSocketChannel()),
    alarmRepositoryProvider.overrideWithValue(repo),
  ];

  Widget buildTestWidget(
    WidgetTester tester, {
    String alarmId = 'alarm-detail-1',
    bool embedded = false,
    ThemeData? theme,
    double textScale = 1.0,
    bool disableAnimations = false,
  }) {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    const size = Size(800, 1200);
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
          home: AlarmDetailsPage(id: alarmId, embedded: embedded),
        ),
      ),
    );
  }

  group('AlarmDetailsPage Widget Tests', () {
    testWidgets('renders shimmer loader when fetching details', (
      WidgetTester tester,
    ) async {
      repo.completer = Completer<TbAlarmInfo>();

      await tester.pumpWidget(buildTestWidget(tester));
      await tester.pump();

      expect(find.byType(TbShimmerList), findsWidgets);
    });

    testWidgets('renders error state and retries successfully', (
      WidgetTester tester,
    ) async {
      repo.shouldThrow = true;

      await tester.pumpWidget(buildTestWidget(tester));
      await tester.pumpAndSettle();

      expect(find.byType(TbEmptyState), findsOneWidget);
      expect(find.text('Failed to load alarm'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);

      repo.shouldThrow = false;
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();

      expect(find.text('High Pressure Alert'), findsWidgets);
    });

    testWidgets('renders full alarm metadata, severity badge, and assignee', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(buildTestWidget(tester));
      await tester.pumpAndSettle();

      expect(find.text('High Pressure Alert'), findsWidgets);
      expect(find.text('Pump Station 1'), findsOneWidget);
      expect(find.byType(TbStatusBadge), findsWidgets);
      expect(find.text('MAJOR'), findsOneWidget);
      expect(find.text('UNACK'), findsOneWidget);

      expect(find.byKey(const Key('alarm-assignee-tile')), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const Key('alarm-assignee-tile')),
          matching: find.text('John Doe'),
        ),
        findsOneWidget,
      );
      expect(find.text('john@example.com'), findsOneWidget);
    });

    testWidgets('confirms and executes Acknowledge dialog', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(buildTestWidget(tester));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('alarm-ack-button')), findsOneWidget);
      await tester.tap(find.byKey(const Key('alarm-ack-button')));
      await tester.pumpAndSettle();

      expect(find.text('Acknowledge alarm?'), findsOneWidget);
      expect(
        find.byKey(const Key('confirm-acknowledge-button')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('confirm-acknowledge-button')));
      await tester.pumpAndSettle();

      expect(repo.ackCalled, isTrue);
      expect(find.text('Alarm acknowledged'), findsOneWidget);
    });

    testWidgets('confirms and executes Clear dialog', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(buildTestWidget(tester));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('alarm-clear-button')), findsOneWidget);
      await tester.tap(find.byKey(const Key('alarm-clear-button')));
      await tester.pumpAndSettle();

      expect(find.text('Clear alarm?'), findsOneWidget);
      expect(find.byKey(const Key('confirm-clear-button')), findsOneWidget);

      await tester.tap(find.byKey(const Key('confirm-clear-button')));
      await tester.pumpAndSettle();

      expect(repo.clearCalled, isTrue);
      expect(find.text('Alarm cleared'), findsOneWidget);
    });

    testWidgets('opens assignee picker bottom sheet and assigns new user', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(buildTestWidget(tester));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('alarm-assignee-tile')));
      await tester.pumpAndSettle();

      expect(find.text('Assign alarm'), findsOneWidget);
      expect(find.text('Alice Smith'), findsOneWidget);
      expect(find.text('Bob Jones'), findsOneWidget);

      await tester.tap(find.byKey(const Key('assignee-option-user-1')));
      await tester.pumpAndSettle();

      expect(repo.assignedId, 'user-1');
      expect(find.text('Assigned to Alice Smith'), findsOneWidget);
    });

    testWidgets('opens assignee picker and unassigns alarm', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(buildTestWidget(tester));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('alarm-assignee-tile')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('assignee-unassign-option')));
      await tester.pumpAndSettle();

      expect(repo.unassignCalled, isTrue);
      expect(find.text('Alarm unassigned'), findsOneWidget);
    });

    testWidgets(
      'displays comments and posts new comment from pinned composer',
      (WidgetTester tester) async {
        await tester.pumpWidget(buildTestWidget(tester));
        await tester.pumpAndSettle();

        expect(find.text('Automatic notification sent'), findsOneWidget);
        expect(find.text('Investigating valve leak'), findsOneWidget);

        await tester.enterText(
          find.byKey(const Key('alarm-comment-input')),
          'Valve replaced and pressure normalized',
        );
        await tester.tap(find.byKey(const Key('alarm-comment-send-button')));
        await tester.pumpAndSettle();

        expect(
          repo.addedComments,
          contains('Valve replaced and pressure normalized'),
        );
        expect(
          find.text('Valve replaced and pressure normalized'),
          findsOneWidget,
        );
      },
    );

    testWidgets('detail sections use TbSectionCard with expected titles', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(buildTestWidget(tester));
      await tester.pumpAndSettle();

      for (final title in const [
        'Actions',
        'Assignee',
        'Timeline & details',
        'Activity',
      ]) {
        expect(
          find.descendant(
            of: find.byType(TbSectionCard),
            matching: find.text(title),
          ),
          findsOneWidget,
          reason: title,
        );
      }
    });

    testWidgets('expands timeline & technical details panel', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(buildTestWidget(tester));
      await tester.pumpAndSettle();

      expect(find.text('Timeline & details'), findsOneWidget);
      await tester.tap(find.text('Timeline & details'));
      await tester.pumpAndSettle();

      expect(find.text('threshold'), findsOneWidget);
      expect(find.text('120 bar'), findsOneWidget);
      expect(find.text('Originator'), findsOneWidget);
      expect(find.text('DEVICE'), findsOneWidget);
    });

    testWidgets('touch targets meet >= 48dp minimum for key buttons', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(buildTestWidget(tester));
      await tester.pumpAndSettle();

      final ackSize = tester.getSize(find.byKey(const Key('alarm-ack-button')));
      expect(ackSize.height, greaterThanOrEqualTo(48.0));

      final clearSize = tester.getSize(
        find.byKey(const Key('alarm-clear-button')),
      );
      expect(clearSize.height, greaterThanOrEqualTo(48.0));

      final sendSize = tester.getSize(
        find.byKey(const Key('alarm-comment-send-button')),
      );
      expect(sendSize.width, greaterThanOrEqualTo(48.0));
      expect(sendSize.height, greaterThanOrEqualTo(48.0));
    });

    testWidgets(
      'renders cleanly in dark theme with 2.0x text scale and reduced motion',
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

        expect(find.text('High Pressure Alert'), findsWidgets);
        expect(tester.takeException(), isNull);
      },
    );
  });
}
