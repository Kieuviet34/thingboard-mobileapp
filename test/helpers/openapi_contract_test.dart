import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'mock_dio_adapter.dart';
import 'openapi_contract.dart';

RequestOptions _req(
  String method,
  String path, {
  Map<String, dynamic>? query,
  Object? data,
}) => RequestOptions(
  method: method,
  path: path,
  queryParameters: query ?? <String, dynamic>{},
  data: data,
);

/// Proves the contract checker itself catches real mistakes (a checker that
/// cannot fail is worthless), so repository contract tests can be trusted.
void main() {
  final contract = OpenApiContract.load();

  test('snapshot is the ThingsBoard PaaS 4.4.x contract', () {
    expect(contract.version, startsWith('4.4'));
    expect(contract.operationKeys, contains('GET /api/v2/alarms'));
  });

  test('accepts a valid paginated alarms request', () {
    final violations = contract.validate(
      _req(
        'GET',
        '/api/v2/alarms',
        query: {
          'page': 0,
          'pageSize': 20,
          'sortProperty': 'createdTime',
          'sortOrder': 'DESC',
          'statusList': ['ACTIVE', 'UNACK'],
          'severityList': ['CRITICAL'],
        },
      ),
    );
    expect(violations, isEmpty);
  });

  test('flags a path that does not exist', () {
    final v = contract.validate(_req('GET', '/api/tenant/assetInfosTypo'));
    expect(v.single, contains('no such operation'));
  });

  test('flags a wrong HTTP method and tells which methods exist', () {
    final v = contract.validate(_req('GET', '/api/alarm/abc/ack'));
    expect(v.single, contains('no such operation'));
  });

  test('flags unknown, missing-required and bad-enum query parameters', () {
    final v = contract.validate(
      _req(
        'GET',
        '/api/v2/alarms',
        query: {
          'page': 0,
          'size': 20, // typo of pageSize
          'sortOrder': 'desc', // enum is case-sensitive
          'statusList': ['OPEN'],
        },
      ),
    );
    expect(v.any((m) => m.contains('unknown query parameter `size`')), isTrue);
    expect(
      v.any((m) => m.contains('required query parameter `pageSize`')),
      isTrue,
    );
    expect(v.any((m) => m.contains('`sortOrder`=`desc`')), isTrue);
    expect(v.any((m) => m.contains('`statusList`=`OPEN`')), isTrue);
  });

  test('flags unknown body fields and bodies the spec does not define', () {
    final bodyTypo = contract.validate(
      _req(
        'POST',
        '/api/alarm/abc/comment',
        data: <String, dynamic>{'commentText': 'hi'},
      ),
    );
    expect(bodyTypo.single, contains('unknown body field `commentText`'));

    final unexpectedBody = contract.validate(
      _req('POST', '/api/alarm/abc/ack', data: <String, dynamic>{'x': 1}),
    );
    expect(unexpectedBody.single, contains('spec defines none'));
  });

  group('response validation', () {
    const validAlarm = <String, dynamic>{
      'id': {'entityType': 'ALARM', 'id': 'a-1'},
      'name': 'High Temperature',
      'type': 'High Temperature',
      'severity': 'CRITICAL',
      'status': 'ACTIVE_UNACK',
      'acknowledged': false,
      'cleared': false,
      'originator': {'entityType': 'DEVICE', 'id': 'd-1'},
    };

    CapturedResponse alarmsResponse(Object? json, {int status = 200}) =>
        CapturedResponse(_req('GET', '/api/v2/alarms'), status, json);

    Map<String, dynamic> page(Map<String, dynamic> item) => {
      'data': [item],
      'totalPages': 1,
      'totalElements': 1,
      'hasNext': false,
    };

    test('accepts a payload shaped like the real server response', () {
      expect(
        contract.validateResponse(alarmsResponse(page(validAlarm))),
        isEmpty,
      );
    });

    test('flags missing required, bad enum, wrong type and unknown fields', () {
      final broken = {...validAlarm}
        ..remove('name')
        ..['severity'] = 'BOGUS'
        ..['acknowledged'] = 'no'
        ..['colour'] = 'red';
      final v = contract
          .validateResponse(alarmsResponse(page(broken)))
          .join('\n');
      expect(v, contains('required response field `name` missing'));
      expect(v, contains('.severity`=`BOGUS` is not one of'));
      expect(v, contains('.acknowledged` should be boolean'));
      expect(v, contains('unknown response field `colour`'));
    });

    test(
      'ignores error statuses, empty bodies and known-wrong spec shapes',
      () {
        expect(
          contract.validateResponse(
            alarmsResponse({'status': 404}, status: 404),
          ),
          isEmpty,
        );
        expect(contract.validateResponse(alarmsResponse(null)), isEmpty);
        // Spec says `string` but the device replies with arbitrary JSON.
        final rpc = CapturedResponse(_req('POST', '/api/rpc/twoway/d-1'), 200, {
          'temperature': 21,
        });
        expect(contract.validateResponse(rpc), isEmpty);
      },
    );
  });

  group('deeper request checks', () {
    test('nested body objects are validated, not only top-level keys', () {
      final v = contract.validate(
        _req(
          'POST',
          '/api/notification/settings/user',
          data: {
            'prefs': {
              'ALARM': {'enabled': true}, // enabledDeliveryMethods is required
            },
          },
        ),
      );
      expect(
        v.join('\n'),
        contains('required body field `enabledDeliveryMethods`'),
      );
    });

    test('required header parameters must be sent', () {
      RequestOptions session({Map<String, dynamic>? headers}) => RequestOptions(
        method: 'POST',
        path: '/api/user/mobile/session',
        data: {'fcmTokenTimestamp': 1},
        headers: headers,
      );
      expect(
        contract.validate(session()).join('\n'),
        contains('required header `X-Mobile-Token` missing'),
      );
      expect(
        contract.validate(session(headers: {'x-mobile-token': 'fcm-1'})),
        isEmpty,
      );
    });
  });

  test('path parameters match any concrete id, literals win over params', () {
    expect(
      contract.matchOperation('GET', '/api/alarm/info/9f6c'),
      'GET /api/alarm/info/{alarmId}',
    );
    expect(
      contract.matchOperation('GET', '/api/user/settings/general'),
      isNotNull,
    );
  });
}
