import 'package:flutter_test/flutter_test.dart';
import 'package:thingsboard_democloud_app/core/models/models.dart';

void main() {
  group('Domain models JSON parsing & immutability', () {
    group('TbDeviceInfo', () {
      Map<String, dynamic> json([Map<String, dynamic> extra = const {}]) =>
          <String, dynamic>{
            'id': {'entityType': 'DEVICE', 'id': 'dev-1'},
            'name': 'Pump-1',
            'type': 'pump-type',
            ...extra,
          };

      test('deviceProfileName comes from deviceProfileName, not type', () {
        final d = TbDeviceInfo.fromJson(
          json({'deviceProfileName': 'Pump Profile'}),
        );
        expect(d.type, 'pump-type');
        expect(d.deviceProfileName, 'Pump Profile');
      });

      test('deviceProfileName falls back to type when absent', () {
        expect(TbDeviceInfo.fromJson(json()).deviceProfileName, 'pump-type');
      });

      test('active parses bool, string and missing', () {
        expect(TbDeviceInfo.fromJson(json({'active': true})).active, isTrue);
        expect(TbDeviceInfo.fromJson(json({'active': 'true'})).active, isTrue);
        expect(
          TbDeviceInfo.fromJson(json({'active': 'false'})).active,
          isFalse,
        );
        expect(TbDeviceInfo.fromJson(json()).active, isFalse);
      });

      test('ownerName wins over customerTitle, which is the fallback', () {
        final both = TbDeviceInfo.fromJson(
          json({'ownerName': 'Owner Inc', 'customerTitle': 'Cust Ltd'}),
        );
        final onlyTitle = TbDeviceInfo.fromJson(
          json({'customerTitle': 'Cust Ltd'}),
        );
        expect(both.ownerName, 'Owner Inc');
        expect(onlyTitle.ownerName, 'Cust Ltd');
        expect(TbDeviceInfo.fromJson(json()).ownerName, '');
      });

      test('null-uuid customerId normalizes to null', () {
        final nullCustomer = TbDeviceInfo.fromJson(
          json({
            'customerId': {
              'entityType': 'CUSTOMER',
              'id': TbDeviceInfo.nullUuid,
            },
          }),
        );
        final realCustomer = TbDeviceInfo.fromJson(
          json({
            'customerId': {'entityType': 'CUSTOMER', 'id': 'cust-1'},
          }),
        );
        expect(nullCustomer.customerId, isNull);
        expect(realCustomer.customerId, 'cust-1');
      });

      test('createdTime parses num to int, missing is 0', () {
        expect(
          TbDeviceInfo.fromJson(
            json({'createdTime': 1704067200000.0}),
          ).createdTime,
          1704067200000,
        );
        expect(TbDeviceInfo.fromJson(json()).createdTime, 0);
      });

      test('copyWith(active:) keeps profile name, owner and created', () {
        final d = TbDeviceInfo.fromJson(
          json({
            'deviceProfileName': 'Pump Profile',
            'ownerName': 'Owner Inc',
            'createdTime': 1704067200000,
            'label': 'Boiler room',
            'active': false,
          }),
        );
        final c = d.copyWith(active: true);
        expect(c.active, isTrue);
        expect(c.deviceProfileName, 'Pump Profile');
        expect(c.ownerName, 'Owner Inc');
        expect(c.createdTime, 1704067200000);
        expect(c.label, 'Boiler room');
        expect(c.type, 'pump-type');
      });

      test('equality changes when profile name, owner or label change', () {
        final base = <String, dynamic>{
          'deviceProfileName': 'A',
          'ownerName': 'O',
          'label': 'L',
        };
        final d = TbDeviceInfo.fromJson(json(base));
        expect(TbDeviceInfo.fromJson(json(base)), d);
        expect(TbDeviceInfo.fromJson(json(base)).hashCode, d.hashCode);
        for (final change in <Map<String, dynamic>>[
          {'deviceProfileName': 'B'},
          {'ownerName': 'P'},
          {'label': 'M'},
          {'createdTime': 5},
        ]) {
          expect(TbDeviceInfo.fromJson(json({...base, ...change})), isNot(d));
        }
      });
    });

    test('PageData parses items and pagination metadata', () {
      final page = PageData<TbDeviceInfo>.fromJson(<String, dynamic>{
        'data': [
          <String, dynamic>{
            'id': {'entityType': 'DEVICE', 'id': 'dev-100'},
            'name': 'Thermo-1',
            'type': 'thermostat',
            'label': 'Lobby',
            'active': true,
            'createdTime': 1704067200000,
            'ownerName': 'Acme',
          },
        ],
        'totalPages': 3,
        'totalElements': 25,
        'hasNext': true,
      }, TbDeviceInfo.fromJson);

      expect(page.data, hasLength(1));
      expect(page.data.first.id, 'dev-100');
      expect(page.data.first.active, isTrue);
      expect(page.totalPages, 3);
      expect(page.totalElements, 25);
      expect(page.hasNext, isTrue);
    });

    test(
      'TbAlarmInfo parses and copyWith(clearAssignee: true) clears assignee',
      () {
        final alarm = TbAlarmInfo.fromJson(<String, dynamic>{
          'id': {'entityType': 'ALARM', 'id': 'alm-1'},
          'type': 'High Temperature',
          'severity': 'CRITICAL',
          'acknowledged': false,
          'cleared': false,
          'createdTime': 1704067200000,
          'originator': {'entityType': 'DEVICE', 'id': 'dev-1'},
          'originatorName': 'Thermostat-3',
          'assigneeId': {'entityType': 'USER', 'id': 'usr-1'},
          'assignee': {
            'firstName': 'Jane',
            'lastName': 'Doe',
            'email': 'jane@tb.io',
          },
        });

        expect(alarm.severity, AlarmSeverity.critical);
        expect(alarm.assigneeName, 'Jane Doe');
        expect(alarm.assigneeId, 'usr-1');

        final unassigned = alarm.copyWith(clearAssignee: true);
        expect(unassigned.assigneeId, isNull);
        expect(unassigned.assigneeName, isNull);
        expect(unassigned.assigneeEmail, isNull);
      },
    );

    test(
      'TbTsPoint safely parses numeric, stringified, and boolean values',
      () {
        final numeric = TbTsPoint.fromJson(<String, dynamic>{
          'ts': 1000,
          'value': 24.5,
        });
        final stringified = TbTsPoint.fromJson(<String, dynamic>{
          'ts': 2000,
          'value': '31.25',
        });
        final text = TbTsPoint.fromJson(<String, dynamic>{
          'ts': 3000,
          'value': 'ONLINE',
        });

        expect(numeric.numericValue, 24.5);
        expect(stringified.numericValue, 31.25);
        expect(text.numericValue, isNull);
        expect(text.displayValue, 'ONLINE');
      },
    );

    test('LoginResponse parses scope Authority and refreshToken', () {
      final login = LoginResponse.fromJson(<String, dynamic>{
        'token': 'jwt-access',
        'refreshToken': 'jwt-refresh',
        'scope': 'PRE_VERIFICATION_TOKEN',
      });

      expect(login.token, 'jwt-access');
      expect(login.refreshToken, 'jwt-refresh');
      expect(login.scope, Authority.preVerificationToken);
    });

    test(
      'TbNotification, TbAuditLog, TbCustomerInfo, and TbUserProfile parse',
      () {
        final notif = TbNotification.fromJson(<String, dynamic>{
          'id': {'entityType': 'NOTIFICATION', 'id': 'n-1'},
          'subject': 'Alarm',
          'text': 'Overheat',
          'createdTime': 123456,
          'status': 'SENT',
          'info': {'alarmSeverity': 'MAJOR'},
        });
        expect(notif.isRead, isFalse);
        expect(notif.severity, AlarmSeverity.major);

        final log = TbAuditLog.fromJson(<String, dynamic>{
          'id': 'log-1',
          'entityId': {'entityType': 'DEVICE', 'id': 'dev-1'},
          'entityName': 'Pump-1',
          'actionType': 'RPC_CALL',
          'actionStatus': 'FAILURE',
          'actionFailureDetails': 'Timeout',
          'createdTime': 999,
        });
        expect(log.entityType, EntityType.device);
        expect(log.isSuccess, isFalse);
        expect(log.failureDetails, 'Timeout');

        final customer = TbCustomerInfo.fromJson(<String, dynamic>{
          'id': {'entityType': 'CUSTOMER', 'id': 'c-1'},
          'title': 'Acme Corp',
          'city': 'San Francisco',
          'state': 'CA',
          'country': 'USA',
        });
        expect(customer.locationSummary, 'San Francisco, CA, USA');

        final user = TbUserProfile.fromJson(<String, dynamic>{
          'id': {'entityType': 'USER', 'id': 'u-1'},
          'email': 'tenant@tb.io',
          'authority': 'TENANT_ADMIN',
          'firstName': 'John',
          'lastName': 'Doe',
        });
        expect(user.displayName, 'John Doe');
        expect(user.initials, 'JD');
      },
    );
  });
}
