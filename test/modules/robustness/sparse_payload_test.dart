import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:thingsboard_democloud_app/config/themes/tb_theme.dart';
import 'package:thingsboard_democloud_app/core/api/controllers/server_config_controller.dart';
import 'package:thingsboard_democloud_app/modules/alarm/alarm_details_page.dart';
import 'package:thingsboard_democloud_app/modules/alarm/alarms_page.dart';
import 'package:thingsboard_democloud_app/modules/asset/asset_details_page.dart';
import 'package:thingsboard_democloud_app/modules/asset/assets_page.dart';
import 'package:thingsboard_democloud_app/modules/audit_log/audit_logs_page.dart';
import 'package:thingsboard_democloud_app/modules/customer/customer_details_page.dart';
import 'package:thingsboard_democloud_app/modules/customer/customers_page.dart';
import 'package:thingsboard_democloud_app/modules/dashboard/dashboards_page.dart';
import 'package:thingsboard_democloud_app/modules/device/device_details_page.dart';
import 'package:thingsboard_democloud_app/modules/device/devices_list_page.dart';
import 'package:thingsboard_democloud_app/modules/home/home_page.dart';
import 'package:thingsboard_democloud_app/modules/notification/notifications_page.dart';
import 'package:thingsboard_democloud_app/widgets/tb_empty_state.dart';

import '../../helpers/fake_app_preferences.dart';
import '../../helpers/fake_secure_storage.dart';
import '../../helpers/fake_ws_channel.dart';
import '../../helpers/mock_dio_adapter.dart';

/// Robustness sweep: live-mode screens fed sparse, null, oversized, empty,
/// failing and malformed HTTP bodies through the mocked Dio boundary.
///
/// Every case asserts: no exception (overflow included), no spinner left after
/// settling (hang), and the scenario-specific state (empty/error/permission).
/// Failing cases are app bugs; do not weaken an expectation to make one pass.

// ---------------------------------------------------------------------------
// Fake payload vocabulary
// ---------------------------------------------------------------------------

/// 252 characters, no spaces: forces word-wrap/overflow paths.
final String _longNoSpaces = 'SensorChannelTemperatureHumidityCalibration' * 6;

/// Vietnamese diacritics, emoji, Arabic (RTL) and CJK in one string.
const String _unicodeText = 'Cảm biến nhiệt độ 🌡️ مستشعر الحرارة ✓ 日本語テスト';

enum _Sample { minimal, nulls, long, healthy }

/// One ThingsBoard entity as it appears in a list or detail response.
class _Entity {
  const _Entity({
    required this.entityType,
    required this.id,
    required this.healthy,
    this.text = const [],
    this.other = const [],
  });

  final String entityType;
  final String id;

  /// Complete, realistic payload covering every key the model reads.
  final Map<String, Object?> healthy;

  /// Free-text keys: get long / Unicode values in the `long` sample.
  final List<String> text;

  /// Optional non-text keys: explicit `null` in the `nulls` sample.
  final List<String> other;

  Map<String, Object?> sample(_Sample kind) {
    final idObj = <String, Object?>{'entityType': entityType, 'id': id};
    return switch (kind) {
      _Sample.minimal => {'id': idObj},
      _Sample.healthy => {'id': idObj, ...healthy},
      _Sample.nulls => {
        'id': idObj,
        ...healthy,
        for (final k in other) k: null,
        for (var i = 0; i < text.length; i++) text[i]: i.isEven ? null : '',
      },
      _Sample.long => {
        'id': idObj,
        ...healthy,
        for (var i = 0; i < text.length; i++)
          text[i]: i.isEven ? _longNoSpaces : _unicodeText,
      },
    };
  }
}

const _alarmEntity = _Entity(
  entityType: 'ALARM',
  id: 'alarm-1',
  healthy: {
    'type': 'High Temperature',
    'severity': 'CRITICAL',
    'status': 'ACTIVE_UNACK',
    'acknowledged': false,
    'cleared': false,
    'createdTime': 1700000000000,
    'originatorName': 'Office Sensor',
    'originatorDisplayName': 'Office Sensor',
  },
  text: ['type', 'originatorName', 'originatorDisplayName'],
  other: ['severity', 'status', 'acknowledged', 'cleared', 'createdTime'],
);

const _deviceEntity = _Entity(
  entityType: 'DEVICE',
  id: 'dev-1',
  healthy: {
    'name': 'Temperature Sensor 01',
    'type': 'Thermometer',
    'label': 'Floor 1 Room 101',
    'active': true,
    'ownerName': 'Tenant Admin',
    'createdTime': 1700000000000,
    'deviceProfileId': {'entityType': 'DEVICE_PROFILE', 'id': 'prof-1'},
  },
  text: ['name', 'type', 'label', 'ownerName'],
  other: ['active', 'createdTime', 'deviceProfileId'],
);

const _assetEntity = _Entity(
  entityType: 'ASSET',
  id: 'asset-1',
  healthy: {
    'name': 'Building A',
    'type': 'Building',
    'label': 'Headquarters',
    'ownerName': 'Tenant Admin',
    'createdTime': 1700000000000,
    'assetProfileId': {'entityType': 'ASSET_PROFILE', 'id': 'aprof-1'},
  },
  text: ['name', 'type', 'label', 'ownerName'],
  other: ['createdTime', 'assetProfileId'],
);

const _customerEntity = _Entity(
  entityType: 'CUSTOMER',
  id: 'cust-1',
  healthy: {
    'title': 'Acme Renewables',
    'country': 'Germany',
    'state': 'Berlin',
    'city': 'Berlin',
    'address': 'Main Street 1',
    'zip': '10115',
    'phone': '+49 30 123456',
    'email': 'info@example.test',
    'createdTime': 1700000000000,
  },
  text: [
    'title',
    'country',
    'state',
    'city',
    'address',
    'zip',
    'phone',
    'email',
  ],
  other: ['createdTime'],
);

const _dashboardEntity = _Entity(
  entityType: 'DASHBOARD',
  id: 'dash-1',
  healthy: {
    'title': 'Energy Overview',
    'image': null,
    'mobileHide': false,
    'mobileOrder': 1,
    'assignedCustomers': [],
    'createdTime': 1700000000000,
  },
  text: ['title'],
  other: ['image', 'mobileOrder', 'assignedCustomers', 'createdTime'],
);

const _notificationEntity = _Entity(
  entityType: 'NOTIFICATION',
  id: 'n-1',
  healthy: {
    'subject': 'Alarm raised',
    'text': 'Temperature above limit',
    'type': 'ALARM',
    'deliveryMethod': 'WEB',
    'status': 'SENT',
    'read': false,
    'createdTime': 1700000000000,
  },
  text: ['subject', 'text'],
  other: ['type', 'deliveryMethod', 'status', 'read', 'createdTime'],
);

const _auditEntity = _Entity(
  entityType: 'AUDIT_LOG',
  id: 'al-1',
  healthy: {
    'entityName': 'Temperature Sensor 01',
    'actionType': 'ADDED',
    'actionStatus': 'SUCCESS',
    'userName': 'tenant-admin',
    'createdTime': 1700000000000,
    'actionFailureDetails': null,
  },
  text: ['entityName', 'userName'],
  other: ['actionType', 'actionStatus', 'createdTime', 'actionFailureDetails'],
);

const _profileEntity = _Entity(
  entityType: 'DEVICE_PROFILE',
  id: 'prof-1',
  healthy: {'name': 'Thermometer'},
  text: ['name'],
);

// ---------------------------------------------------------------------------
// Screens under test
// ---------------------------------------------------------------------------

/// One GET endpoint a screen depends on, and the entity it returns.
class _Endpoint {
  const _Endpoint(this.path, this.entity, {this.isList = true});

  final String path;
  final _Entity entity;

  /// `true`: paged envelope `{data, totalPages, ...}`. `false`: single entity.
  final bool isList;
}

enum _Kind { list, detail, home }

class _Page {
  const _Page({
    required this.name,
    required this.kind,
    required this.endpoints,
    required this.build,
  });

  final String name;
  final _Kind kind;

  /// The first endpoint is the screen's primary data source.
  final List<_Endpoint> endpoints;
  final Widget Function() build;
}

final _pages = <_Page>[
  _Page(
    name: 'Alarms list',
    kind: _Kind.list,
    endpoints: const [_Endpoint('/api/v2/alarms', _alarmEntity)],
    build: () => AlarmsPage(),
  ),
  _Page(
    name: 'Devices list',
    kind: _Kind.list,
    endpoints: const [_Endpoint('/api/deviceInfos/all', _deviceEntity)],
    build: () => DevicesListPage(),
  ),
  _Page(
    name: 'Assets list',
    kind: _Kind.list,
    endpoints: const [_Endpoint('/api/assetInfos/all', _assetEntity)],
    build: () => AssetsPage(),
  ),
  _Page(
    name: 'Customers list',
    kind: _Kind.list,
    endpoints: const [_Endpoint('/api/customerInfos/all', _customerEntity)],
    build: () => CustomersPage(),
  ),
  _Page(
    name: 'Dashboards list',
    kind: _Kind.list,
    endpoints: const [_Endpoint('/api/user/dashboards', _dashboardEntity)],
    build: () => DashboardsPage(),
  ),
  _Page(
    name: 'Notifications list',
    kind: _Kind.list,
    endpoints: const [_Endpoint('/api/notifications', _notificationEntity)],
    build: () => NotificationsPage(),
  ),
  _Page(
    name: 'Audit logs list',
    kind: _Kind.list,
    endpoints: const [_Endpoint('/api/audit/logs', _auditEntity)],
    build: () => AuditLogsPage(),
  ),
  _Page(
    name: 'Home',
    kind: _Kind.home,
    endpoints: const [
      _Endpoint('/api/v2/alarms', _alarmEntity),
      _Endpoint('/api/user/dashboards', _dashboardEntity),
      _Endpoint('/api/deviceProfileInfos', _profileEntity),
    ],
    build: () => HomePage(),
  ),
  _Page(
    name: 'Device details',
    kind: _Kind.detail,
    endpoints: const [
      _Endpoint('/api/device/info/dev-1', _deviceEntity, isList: false),
    ],
    build: () => DeviceDetailsPage(deviceId: 'dev-1'),
  ),
  _Page(
    name: 'Asset details',
    kind: _Kind.detail,
    endpoints: const [
      _Endpoint('/api/asset/info/asset-1', _assetEntity, isList: false),
    ],
    build: () => AssetDetailsPage(assetId: 'asset-1'),
  ),
  _Page(
    name: 'Customer details',
    kind: _Kind.detail,
    endpoints: const [
      _Endpoint('/api/customer/info/cust-1', _customerEntity, isList: false),
    ],
    build: () => CustomerDetailsPage(customerId: 'cust-1'),
  ),
  _Page(
    name: 'Alarm details',
    kind: _Kind.detail,
    endpoints: const [
      _Endpoint('/api/alarm/info/alarm-1', _alarmEntity, isList: false),
    ],
    build: () => AlarmDetailsPage(id: 'alarm-1'),
  ),
];

// ---------------------------------------------------------------------------
// Scenarios and viewport variants
// ---------------------------------------------------------------------------

enum _Scenario {
  minimal('1 minimal item'),
  nullsAndEmpty('2 explicit nulls and empty strings'),
  longUnicode('3 200+ char and Unicode/RTL text'),
  emptyPage('4 empty page'),
  http500('5a HTTP 500'),
  networkError('5b network connection error'),
  http403('6 HTTP 403'),
  nullBody('7a null body'),
  nonJsonBody('7b non-JSON body'),
  listBody('7c list instead of map'),
  // Control: a complete payload. Proves a failure elsewhere is data-driven,
  // and is the body a successful Retry returns.
  healthy('control: full valid payload');

  const _Scenario(this.label);
  final String label;
}

const _testedScenarios = [
  _Scenario.healthy,
  _Scenario.minimal,
  _Scenario.nullsAndEmpty,
  _Scenario.longUnicode,
  _Scenario.emptyPage,
  _Scenario.http500,
  _Scenario.networkError,
  _Scenario.http403,
  _Scenario.nullBody,
  _Scenario.nonJsonBody,
  _Scenario.listBody,
];

class _Variant {
  const _Variant(this.label, {required this.dark, required this.textScale});

  final String label;
  final bool dark;
  final double textScale;
}

const _variants = [
  _Variant('light 1.0x', dark: false, textScale: 1.0),
  _Variant('light 2.0x', dark: false, textScale: 2.0),
  _Variant('dark 1.0x', dark: true, textScale: 1.0),
  _Variant('dark 2.0x', dark: true, textScale: 2.0),
];

// ---------------------------------------------------------------------------
// Mock HTTP wiring
// ---------------------------------------------------------------------------

Map<String, Object?> _envelope(List<Object?> items) => {
  'data': items,
  'totalPages': items.isEmpty ? 0 : 1,
  'totalElements': items.length,
  'hasNext': false,
};

/// [MockDioAdapter] that also answers the detail screens' secondary calls
/// (telemetry, relations, comments, assignees, RPC, credentials) with healthy
/// empty data when no explicit route was registered. Without this those calls
/// 404 and their sections show Retry, which says nothing about the payload.
class _ScreenAdapter extends MockDioAdapter {
  final Set<String> _registered = <String>{};

  @override
  void on(String method, String path, MockRouteHandler handler) {
    _registered.add('${method.toUpperCase()} $path');
    super.on(method, path, handler);
  }

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    final key = '${options.method.toUpperCase()} ${options.path}';
    final fallback = _registered.contains(key)
        ? null
        : _secondaryFallback(options);
    if (fallback != null) {
      capturedRequests.add(options);
      return Future.value(fallback);
    }
    return super.fetch(options, requestStream, cancelFuture);
  }

  static ResponseBody? _secondaryFallback(RequestOptions o) {
    final path = o.path;
    if (path.contains('/values/attributes')) {
      return MockDioAdapter.jsonResponse(const <Object?>[]);
    }
    if (path.startsWith('/api/plugins/telemetry/')) {
      return MockDioAdapter.jsonResponse(<String, Object?>{});
    }
    if (path.startsWith('/api/relations/')) {
      return MockDioAdapter.jsonResponse(const <Object?>[]);
    }
    if (path.startsWith('/api/device/') && path.endsWith('/credentials')) {
      return MockDioAdapter.jsonResponse({
        'id': {'entityType': 'DEVICE_CREDENTIALS', 'id': 'cred-1'},
        'deviceId': {'entityType': 'DEVICE', 'id': 'dev-1'},
        'credentialsType': 'ACCESS_TOKEN',
        'credentialsId': 'token-1',
      });
    }
    if (path.startsWith('/api/alarm/') && path.endsWith('/comment')) {
      return MockDioAdapter.jsonResponse(_envelope(const []));
    }
    if (path.startsWith('/api/users/assign/') ||
        path.startsWith('/api/v2/alarm/') ||
        path.startsWith('/api/rpc/')) {
      return MockDioAdapter.jsonResponse(_envelope(const []));
    }
    return null;
  }
}

/// Healthy, empty answers for every endpoint a screen might touch, so only the
/// endpoint under test varies per case.
void _registerHealthyDefaults(MockDioAdapter adapter) {
  const listPaths = [
    '/api/v2/alarms',
    '/api/deviceInfos/all',
    '/api/deviceProfileInfos',
    '/api/assetInfos/all',
    '/api/assetProfileInfos',
    '/api/customerInfos/all',
    '/api/user/dashboards',
    '/api/notifications',
    '/api/audit/logs',
  ];
  for (final path in listPaths) {
    adapter.on(
      'GET',
      path,
      (_) => MockDioAdapter.jsonResponse(_envelope(const [])),
    );
  }
  adapter.on(
    'GET',
    '/api/notifications/unread/count',
    (_) => MockDioAdapter.jsonResponse(0),
  );
  adapter.on(
    'GET',
    '/api/user/lastVisitedDashboards',
    (_) => MockDioAdapter.jsonResponse(<String, dynamic>{}),
  );
  adapter.on(
    'POST',
    '/api/entitiesQuery/count',
    (_) => MockDioAdapter.jsonResponse(0),
  );
}

Object? _payloadFor(_Endpoint e, _Scenario s) {
  final kind = switch (s) {
    _Scenario.minimal => _Sample.minimal,
    _Scenario.nullsAndEmpty => _Sample.nulls,
    _Scenario.longUnicode => _Sample.long,
    _ => _Sample.healthy,
  };
  if (!e.isList) {
    return s == _Scenario.emptyPage
        ? <String, Object?>{}
        : e.entity.sample(kind);
  }
  final items = s == _Scenario.emptyPage
      ? <Object?>[]
      : <Object?>[e.entity.sample(kind)];
  return _envelope(items);
}

FutureOr<ResponseBody> _respond(
  RequestOptions options,
  _Endpoint e,
  _Scenario s,
) {
  switch (s) {
    case _Scenario.http500:
      return MockDioAdapter.jsonResponse({
        'status': 500,
        'message': 'Internal server error',
      }, statusCode: 500);
    case _Scenario.networkError:
      throw DioException.connectionError(
        requestOptions: options,
        reason: 'simulated: no route to host',
      );
    case _Scenario.http403:
      return MockDioAdapter.jsonResponse({
        'status': 403,
        'message': "You don't have permission to do this",
      }, statusCode: 403);
    case _Scenario.nullBody:
      return ResponseBody.fromString('', 200);
    case _Scenario.nonJsonBody:
      return ResponseBody.fromString(
        '<html><body>502 Bad Gateway</body></html>',
        200,
        headers: {
          Headers.contentTypeHeader: ['text/html; charset=utf-8'],
        },
      );
    case _Scenario.listBody:
      return MockDioAdapter.jsonResponse([e.entity.sample(_Sample.healthy)]);
    default:
      return MockDioAdapter.jsonResponse(_payloadFor(e, s));
  }
}

void _route(MockDioAdapter adapter, _Endpoint e, _Scenario s) {
  adapter.on('GET', e.path, (options) => _respond(options, e, s));
}

// ---------------------------------------------------------------------------
// Harness
// ---------------------------------------------------------------------------

void _configureViewport(WidgetTester tester, _Variant v) {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  tester.platformDispatcher.textScaleFactorTestValue = v.textScale;
  addTearDown(tester.platformDispatcher.clearAllTestValues);
}

Widget _app(Widget page, MockDioAdapter adapter, _Variant v) {
  return ProviderScope(
    overrides: [
      tbStorageProvider.overrideWithValue(FakeSecureStorage()),
      tbAppPreferencesProvider.overrideWithValue(FakeAppPreferences()),
      tbHttpClientAdapterProvider.overrideWithValue(adapter),
      wsChannelFactoryProvider.overrideWithValue((_) => FakeWebSocketChannel()),
    ],
    child: MediaQuery(
      data: MediaQueryData(
        size: const Size(390, 844),
        textScaler: TextScaler.linear(v.textScale),
      ),
      child: MaterialApp(
        theme: v.dark ? tbDarkTheme() : tbLightTheme(),
        home: page,
      ),
    ),
  );
}

/// Pumps fixed frames instead of `pumpAndSettle`, so a looping shimmer shows up
/// as a visible spinner rather than a settle timeout.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 40; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

bool _isSpinning() {
  return find
      .byWidgetPredicate(
        (w) =>
            w is ProgressIndicator ||
            w.runtimeType.toString().contains('Shimmer'),
      )
      .evaluate()
      .isNotEmpty;
}

String _outcome() {
  final titles = find
      .byType(TbEmptyState)
      .evaluate()
      .map((e) => (e.widget as TbEmptyState).title)
      .join(' / ');
  if (titles.isNotEmpty) return 'state[$titles]';
  return 'content';
}

/// Framework error text (with the overflowing widget's creator location) for
/// the case that is running. `takeException()` alone keeps only the summary.
String _frameworkDetail = '';

void _captureFrameworkErrors() {
  final previous = FlutterError.onError;
  addTearDown(() => FlutterError.onError = previous);
  FlutterError.onError = (details) {
    final collected = details.informationCollector?.call() ?? const [];
    _frameworkDetail = collected.map((n) => n.toDescription()).join(' | ');
    previous?.call(details);
  };
}

void _expectNoCrashOrHang(WidgetTester tester, String label) {
  final error = tester.takeException();
  expect(
    error,
    isNull,
    reason:
        '$label: exception while rendering: $error'
        '${_frameworkDetail.isEmpty ? '' : ' [$_frameworkDetail]'}',
  );
  expect(
    _isSpinning(),
    isFalse,
    reason: '$label: spinner still visible after settling (hang)',
  );
}

Future<void> _runCase(
  WidgetTester tester,
  _Page page,
  _Scenario s,
  _Variant v,
) async {
  final label = '${page.name} | ${s.label} | ${v.label}';
  _configureViewport(tester, v);
  _frameworkDetail = '';
  _captureFrameworkErrors();

  final adapter = _ScreenAdapter();
  _registerHealthyDefaults(adapter);
  for (final e in page.endpoints) {
    _route(adapter, e, s);
  }

  await tester.pumpWidget(_app(page.build(), adapter, v));
  await _settle(tester);
  _expectNoCrashOrHang(tester, label);

  // Home aggregates several sections; it is only held to the no-crash rule.
  final isHome = page.kind == _Kind.home;

  if (s == _Scenario.emptyPage && page.kind == _Kind.list) {
    expect(find.byType(TbEmptyState), findsOneWidget, reason: label);
    expect(
      find.descendant(
        of: find.byType(TbEmptyState),
        matching: find.byType(FilledButton),
      ),
      findsOneWidget,
      reason: '$label: empty state should expose exactly one action',
    );
  }

  if ((s == _Scenario.http500 || s == _Scenario.networkError) && !isHome) {
    expect(find.byType(TbEmptyState), findsWidgets, reason: label);
    expect(find.text('Retry'), findsWidgets, reason: '$label: no Retry action');

    for (final e in page.endpoints) {
      _route(adapter, e, _Scenario.healthy);
    }
    await tester.tap(find.text('Retry').first);
    await _settle(tester);
    _expectNoCrashOrHang(tester, '$label after Retry');
    expect(
      find.text('Retry'),
      findsNothing,
      reason: '$label: Retry still shown after a successful reload',
    );
  }

  if (s == _Scenario.http403 && !isHome) {
    expect(find.text('Access Restricted'), findsWidgets, reason: label);
    expect(
      find.text('Retry'),
      findsNothing,
      reason: '$label: permission-denied state should not offer Retry',
    );
  }

  debugPrint('[robustness] $label => ${_outcome()}');
}

void main() {
  for (final page in _pages) {
    for (final scenario in _testedScenarios) {
      for (final variant in _variants) {
        testWidgets(
          '${page.name} | ${scenario.label} | ${variant.label}',
          (tester) => _runCase(tester, page, scenario, variant),
        );
      }
    }
  }
}
