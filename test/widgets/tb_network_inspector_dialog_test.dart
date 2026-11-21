import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:thingsboard_democloud_app/config/themes/tb_theme.dart';
import 'package:thingsboard_democloud_app/core/api/client/tb_network_inspector.dart';
import 'package:thingsboard_democloud_app/widgets/tb_network_inspector_dialog.dart';

import '../helpers/mock_dio_adapter.dart';
import '../helpers/test_container.dart';

const _userUrl = 'https://demo.example.com/api/auth/user';
const _loginUrl = 'https://demo.example.com/api/auth/login';
const _devicesUrl = 'https://demo.example.com/api/customer/devices';

TbNetworkLogEntry _entry({
  required String id,
  String method = 'GET',
  String url = _userUrl,
  int? statusCode = 200,
  int? durationMs = 12,
  dynamic requestBody,
  dynamic responseBody,
  String? errorMessage,
  bool isError = false,
  Map<String, dynamic> requestHeaders = const {},
}) {
  return TbNetworkLogEntry(
    id: id,
    timestamp: DateTime(2026, 11, 21, 9, 30, 15),
    method: method,
    url: url,
    statusCode: statusCode,
    durationMs: durationMs,
    requestHeaders: requestHeaders,
    requestBody: requestBody,
    responseBody: responseBody,
    errorMessage: errorMessage,
    isError: isError,
  );
}

/// Matches visible text in both [Text] and [SelectableText] (used for payloads).
Finder _textContaining(String fragment) {
  return find.byWidgetPredicate((widget) {
    final data = switch (widget) {
      Text(:final data) => data,
      SelectableText(:final data) => data,
      _ => null,
    };
    return data != null && data.contains(fragment);
  });
}

/// Creates a container whose log is fed the same way `main.dart` feeds it.
ProviderContainer _connectSink() {
  final container = createTestContainer();
  TbNetworkLog.registerSink(
    (entry) => container.read(tbNetworkLogProvider.notifier).record(entry),
  );
  addTearDown(() => TbNetworkLog.registerSink(null));
  return container;
}

/// Width used by functional tests. Wide enough that the filter chip row fits,
/// so behaviour assertions are not masked by the known phone-width overflow.
/// Phone-width (390dp) layout is checked by dedicated tests below.
const _functionalWidth = 600.0;
const _phoneWidth = 390.0;

/// Pumps a host screen with a button that opens the inspector the way the
/// Settings page does, then opens it.
Future<void> _openInspector(
  WidgetTester tester,
  ProviderContainer container, {
  ThemeData? theme,
  double textScale = 1,
  double width = _functionalWidth,
}) async {
  tester.view
    ..physicalSize = Size(width, 900)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MediaQuery(
        data: MediaQueryData.fromView(
          tester.view,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: MaterialApp(
          theme: theme ?? tbLightTheme(),
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: FilledButton(
                  onPressed: () => TbNetworkInspectorDialog.show(context),
                  child: const Text('Open inspector'),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open inspector'));
  await tester.pumpAndSettle();
}

void _record(ProviderContainer container, TbNetworkLogEntry entry) {
  container.read(tbNetworkLogProvider.notifier).record(entry);
}

void main() {
  group('empty state', () {
    testWidgets('shows zero count and guidance when nothing was recorded', (
      tester,
    ) async {
      final container = _connectSink();
      await _openInspector(tester, container);

      expect(find.text('Data Traffic Inspector'), findsOneWidget);
      expect(find.text('0 captured transactions'), findsOneWidget);
      expect(
        find.text(
          'No network transactions recorded yet.\n'
          'Make requests or perform actions to inspect data.',
        ),
        findsOneWidget,
      );
    });
  });

  group('recorded entries', () {
    testWidgets(
      'renders method, status, latency and URL for each entry, newest first',
      (tester) async {
        final container = _connectSink();
        _record(container, _entry(id: 'a', url: _userUrl));
        _record(
          container,
          _entry(
            id: 'b',
            method: 'POST',
            url: _loginUrl,
            statusCode: 401,
            durationMs: 340,
            isError: true,
            errorMessage: 'Unauthorized',
          ),
        );

        await _openInspector(tester, container);

        expect(find.text('2 captured transactions'), findsOneWidget);
        final list = find.byType(ListView);
        expect(
          find.descendant(of: list, matching: find.text('POST')),
          findsOneWidget,
        );
        expect(
          find.descendant(of: list, matching: find.text('GET')),
          findsOneWidget,
        );
        expect(
          find.descendant(of: list, matching: find.text('401')),
          findsOneWidget,
        );
        expect(
          find.descendant(of: list, matching: find.text('200')),
          findsOneWidget,
        );
        expect(find.text('340ms'), findsOneWidget);
        expect(find.text('12ms'), findsOneWidget);
        expect(find.text('09:30:15'), findsNWidgets(2));
        expect(find.text(_loginUrl), findsOneWidget);
        expect(find.text(_userUrl), findsOneWidget);

        final loginDy = tester.getTopLeft(find.text(_loginUrl)).dy;
        final userDy = tester.getTopLeft(find.text(_userUrl)).dy;
        expect(
          loginDy,
          lessThan(userDy),
          reason: 'newest entry is listed first',
        );
      },
    );

    testWidgets('an entry without an HTTP status shows ERR when it failed', (
      tester,
    ) async {
      final container = _connectSink();
      _record(
        container,
        _entry(
          id: 'x',
          statusCode: null,
          durationMs: null,
          isError: true,
          errorMessage: 'Connection reset',
        ),
      );

      await _openInspector(tester, container);

      expect(find.text('ERR'), findsOneWidget);
      expect(find.textContaining('ms'), findsNothing);
    });

    testWidgets('keeps only the 50 most recent entries', (tester) async {
      final container = _connectSink();
      for (var i = 0; i < 60; i++) {
        _record(container, _entry(id: 'e$i', url: '$_userUrl?seq=$i'));
      }

      await _openInspector(tester, container);

      expect(find.text('50 captured transactions'), findsOneWidget);
      expect(find.text('$_userUrl?seq=59'), findsOneWidget);
      expect(find.text('$_userUrl?seq=9'), findsNothing);
    });
  });

  group('filters', () {
    testWidgets('ERRORS, POST and GET chips narrow the list; ALL restores it', (
      tester,
    ) async {
      final container = _connectSink();
      _record(container, _entry(id: 'get-ok', url: _userUrl));
      _record(
        container,
        _entry(
          id: 'post-err',
          method: 'POST',
          url: _loginUrl,
          statusCode: 401,
          isError: true,
        ),
      );
      _record(
        container,
        _entry(id: 'get-ok-2', url: _devicesUrl, statusCode: 200),
      );

      await _openInspector(tester, container);

      await tester.tap(find.widgetWithText(FilterChip, 'ERRORS'));
      await tester.pumpAndSettle();
      expect(find.text(_loginUrl), findsOneWidget);
      expect(find.text(_userUrl), findsNothing);
      expect(find.text(_devicesUrl), findsNothing);
      expect(
        tester
            .widget<FilterChip>(find.widgetWithText(FilterChip, 'ERRORS'))
            .selected,
        isTrue,
      );
      // The header count is about everything captured, not the filtered view.
      expect(find.text('3 captured transactions'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilterChip, 'POST'));
      await tester.pumpAndSettle();
      expect(find.text(_loginUrl), findsOneWidget);
      expect(find.text(_userUrl), findsNothing);

      await tester.tap(find.widgetWithText(FilterChip, 'GET'));
      await tester.pumpAndSettle();
      expect(find.text(_loginUrl), findsNothing);
      expect(find.text(_userUrl), findsOneWidget);
      expect(find.text(_devicesUrl), findsOneWidget);

      await tester.tap(find.widgetWithText(FilterChip, 'ALL'));
      await tester.pumpAndSettle();
      expect(find.text(_loginUrl), findsOneWidget);
      expect(find.text(_userUrl), findsOneWidget);
      expect(find.text(_devicesUrl), findsOneWidget);
    });

    testWidgets('a filter with no matches explains which filter is active', (
      tester,
    ) async {
      final container = _connectSink();
      _record(
        container,
        _entry(id: 'post', method: 'POST', url: _loginUrl, statusCode: 200),
      );

      await _openInspector(tester, container);
      await tester.tap(find.widgetWithText(FilterChip, 'GET'));
      await tester.pumpAndSettle();

      expect(find.text('No requests matching "GET"'), findsOneWidget);
      expect(find.text(_loginUrl), findsNothing);
    });

    testWidgets('filter chips fit a 390dp phone width without overflow', (
      tester,
    ) async {
      final container = _connectSink();
      _record(container, _entry(id: 'a'));

      await _openInspector(tester, container, width: _phoneWidth);

      expect(tester.takeException(), isNull);
      expect(find.widgetWithText(FilterChip, 'ERRORS'), findsOneWidget);
    });
  });

  group('expanding an entry', () {
    testWidgets(
      'tapping a row reveals request and response payloads, tapping again collapses',
      (tester) async {
        final container = _connectSink();
        _record(
          container,
          _entry(
            id: 'dev',
            url: _devicesUrl,
            requestBody: {'pageSize': 10},
            responseBody: {
              'data': [
                {'name': 'sensor-1'},
              ],
            },
          ),
        );

        await _openInspector(tester, container);
        expect(find.text('REQUEST PAYLOAD'), findsNothing);

        await tester.tap(find.text(_devicesUrl));
        await tester.pumpAndSettle();

        expect(find.text('REQUEST PAYLOAD'), findsOneWidget);
        expect(find.text('RESPONSE DATA'), findsOneWidget);
        expect(_textContaining('"pageSize": 10'), findsWidgets);
        expect(_textContaining('"name": "sensor-1"'), findsWidgets);

        await tester.tap(find.text(_devicesUrl));
        await tester.pumpAndSettle();
        expect(find.text('REQUEST PAYLOAD'), findsNothing);
      },
    );

    testWidgets(
      'an expanded failed entry shows the error and empty payloads as Empty',
      (tester) async {
        final container = _connectSink();
        _record(
          container,
          _entry(
            id: 'err',
            method: 'DELETE',
            url: _devicesUrl,
            statusCode: 504,
            isError: true,
            errorMessage: 'Gateway timeout',
          ),
        );

        await _openInspector(tester, container);
        await tester.tap(find.text(_devicesUrl));
        await tester.pumpAndSettle();

        expect(find.text('Error: Gateway timeout'), findsOneWidget);
        expect(find.text('Empty'), findsNWidgets(2));
      },
    );

    testWidgets('copy button puts the payload on the clipboard and confirms', (
      tester,
    ) async {
      final copied = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied.add((call.arguments as Map)['text'] as String);
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );

      final container = _connectSink();
      _record(
        container,
        _entry(id: 'dev', url: _devicesUrl, requestBody: {'pageSize': 10}),
      );
      await _openInspector(tester, container);
      await tester.tap(find.text(_devicesUrl));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Copy REQUEST PAYLOAD'));
      await tester.pumpAndSettle();

      expect(copied, ['{\n  "pageSize": 10\n}']);
      // Confirmation lives on the button itself: a snackbar would be painted
      // on the root Scaffold, underneath this root-navigator sheet.
      expect(find.byTooltip('Copied REQUEST PAYLOAD'), findsOneWidget);
      expect(find.byIcon(Icons.check_rounded), findsOneWidget);

      await tester.pump(const Duration(seconds: 2));
      expect(find.byTooltip('Copy REQUEST PAYLOAD'), findsOneWidget);
      expect(find.byIcon(Icons.check_rounded), findsNothing);
    });
  });

  group('clear and close', () {
    testWidgets('Clear logs empties the list and shows the empty state', (
      tester,
    ) async {
      final container = _connectSink();
      _record(container, _entry(id: 'a'));
      _record(container, _entry(id: 'b', method: 'POST', url: _loginUrl));
      await _openInspector(tester, container);
      expect(find.text('2 captured transactions'), findsOneWidget);

      await tester.tap(find.byTooltip('Clear logs'));
      await tester.pumpAndSettle();

      expect(container.read(tbNetworkLogProvider), isEmpty);
      expect(find.text('0 captured transactions'), findsOneWidget);
      expect(find.text(_userUrl), findsNothing);
      expect(
        find.textContaining('No network transactions recorded yet'),
        findsOneWidget,
      );
    });

    testWidgets('Close dismisses the inspector', (tester) async {
      final container = _connectSink();
      await _openInspector(tester, container);
      expect(find.byType(TbNetworkInspectorDialog), findsOneWidget);

      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();

      expect(find.byType(TbNetworkInspectorDialog), findsNothing);
    });
  });

  group('long content', () {
    testWidgets(
      'long URLs and payloads do not overflow when collapsed or expanded',
      (tester) async {
        final longUrl =
            '$_devicesUrl/${''.padRight(300, 'a')}?filter=${''.padRight(200, 'b')}';
        final longBody = {'blob': ''.padRight(1500, 'x')};
        final container = _connectSink();
        _record(
          container,
          _entry(
            id: 'long',
            url: longUrl,
            requestBody: longBody,
            responseBody: {'message': ''.padRight(800, 'y')},
          ),
        );

        await _openInspector(tester, container);
        expect(tester.takeException(), isNull);

        await tester.tap(find.textContaining('/api/customer/devices/aaaa'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text('REQUEST PAYLOAD'), findsOneWidget);
      },
    );
  });

  group('secrets', () {
    testWidgets(
      'the interceptor records the Authorization header as Bearer *** and never the raw token',
      (tester) async {
        final container = _connectSink();
        final adapter = MockDioAdapter()
          ..on(
            'GET',
            '/api/auth/user',
            (_) => MockDioAdapter.jsonResponse({'email': 'user@example.com'}),
          );
        final dio = createTestDio(adapter, baseUrl: 'https://demo.example.com')
          ..interceptors.add(TbNetworkLogInterceptor());

        await tester.runAsync(
          () => dio.get<Map<String, dynamic>>(
            '/api/auth/user',
            options: Options(headers: {'X-Authorization': 'Bearer jwt-1'}),
          ),
        );

        final recorded = container.read(tbNetworkLogProvider).single;
        expect(recorded.requestHeaders['X-Authorization'], 'Bearer ***');
        expect(recorded.requestHeaders.toString(), isNot(contains('jwt-1')));

        await _openInspector(tester, container);
        expect(_textContaining('jwt-1'), findsNothing);
        expect(_textContaining('Bearer'), findsNothing);
      },
    );

    testWidgets('a login request password is not shown in the inspector', (
      tester,
    ) async {
      final container = _connectSink();
      final adapter = MockDioAdapter()
        ..on(
          'POST',
          '/api/auth/login',
          (_) => MockDioAdapter.jsonResponse({
            'token': 'jwt-1',
            'refreshToken': 'refresh-1',
          }),
        );
      final dio = createTestDio(adapter, baseUrl: 'https://demo.example.com')
        ..interceptors.add(TbNetworkLogInterceptor());

      await tester.runAsync(
        () => dio.post<Map<String, dynamic>>(
          '/api/auth/login',
          data: {'username': 'user@example.com', 'password': 'pw-secret-1'},
        ),
      );

      await _openInspector(tester, container);
      await tester.tap(find.text(_loginUrl));
      await tester.pumpAndSettle();

      expect(_textContaining('pw-secret-1'), findsNothing);
    });

    testWidgets('a login response token is not shown in the inspector', (
      tester,
    ) async {
      final container = _connectSink();
      final adapter = MockDioAdapter()
        ..on(
          'POST',
          '/api/auth/login',
          (_) => MockDioAdapter.jsonResponse({
            'token': 'jwt-1',
            'refreshToken': 'refresh-1',
          }),
        );
      final dio = createTestDio(adapter, baseUrl: 'https://demo.example.com')
        ..interceptors.add(TbNetworkLogInterceptor());

      await tester.runAsync(
        () => dio.post<Map<String, dynamic>>(
          '/api/auth/login',
          data: {'username': 'user@example.com', 'password': 'pw-secret-1'},
        ),
      );

      await _openInspector(tester, container);
      await tester.tap(find.text(_loginUrl));
      await tester.pumpAndSettle();

      expect(_textContaining('jwt-1'), findsNothing);
      expect(_textContaining('refresh-1'), findsNothing);
    });

    testWidgets(
      'a 2FA verification code sent as a query parameter is not shown in the URL',
      (tester) async {
        final container = _connectSink();
        final adapter = MockDioAdapter()
          ..on(
            'POST',
            '/api/auth/2fa/verification/check',
            (_) => MockDioAdapter.jsonResponse({'token': 'jwt-1'}),
          );
        final dio = createTestDio(adapter, baseUrl: 'https://demo.example.com')
          ..interceptors.add(TbNetworkLogInterceptor());

        await tester.runAsync(
          () => dio.post<Map<String, dynamic>>(
            '/api/auth/2fa/verification/check',
            queryParameters: {
              'providerType': 'TOTP',
              'verificationCode': '123456',
            },
          ),
        );

        await _openInspector(tester, container);

        expect(_textContaining('123456'), findsNothing);
      },
    );
  });

  group('accessibility and layout', () {
    testWidgets('meets Android tap-target and labelled tap-target guidelines', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      final container = _connectSink();
      _record(container, _entry(id: 'a'));
      _record(
        container,
        _entry(
          id: 'b',
          method: 'POST',
          url: _loginUrl,
          statusCode: 401,
          isError: true,
        ),
      );
      await _openInspector(tester, container);

      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));

      semantics.dispose();
    });

    testWidgets('entry rows survive 2.0x text scale without overflow', (
      tester,
    ) async {
      final container = _connectSink();
      _record(
        container,
        _entry(
          id: 'a',
          method: 'POST',
          url: _loginUrl,
          statusCode: 401,
          durationMs: 1234,
          isError: true,
          errorMessage: 'Unauthorized',
        ),
      );
      await _openInspector(tester, container, textScale: 2, width: _phoneWidth);

      expect(tester.takeException(), isNull);
      expect(find.text(_loginUrl), findsOneWidget);

      await tester.tap(find.text(_loginUrl));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Error: Unauthorized'), findsOneWidget);
    });

    testWidgets('renders in dark theme with entries and filters', (
      tester,
    ) async {
      final container = _connectSink();
      _record(container, _entry(id: 'a'));
      await _openInspector(tester, container, theme: tbDarkTheme());

      expect(tester.takeException(), isNull);
      expect(find.text('1 captured transactions'), findsOneWidget);
      expect(find.widgetWithText(FilterChip, 'ALL'), findsOneWidget);
    });
  });
}
