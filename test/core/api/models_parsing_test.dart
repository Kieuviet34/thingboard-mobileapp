import 'package:flutter_test/flutter_test.dart';
import 'package:thingsboard_democloud_app/core/models/models.dart';

void main() {
  group('Domain models JSON parsing & immutability', () {
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
