import 'package:flutter_test/flutter_test.dart';
import 'package:thingsboard_democloud_app/core/api/client/tb_network_redactor.dart';

void main() {
  const mask = TbNetworkRedactor.mask;

  group('redactBody', () {
    test('masks credentials in a login request, any casing or separator', () {
      final redacted =
          TbNetworkRedactor.redactBody({
                'username': 'user@example.com',
                'password': 'pw-secret-1',
                'Refresh_Token': 'refresh-1',
              })
              as Map;
      expect(redacted['username'], 'user@example.com');
      expect(redacted['password'], mask);
      expect(redacted['Refresh_Token'], mask);
    });

    test('masks tokens in responses and nested/list structures', () {
      final redacted =
          TbNetworkRedactor.redactBody({
                'token': 'jwt-1',
                'refreshToken': 'refresh-1',
                'scope': 'TENANT_ADMIN',
                'devices': [
                  {
                    'name': 'Sensor',
                    'credentials': {'credentialsId': 'ACCESS-TOKEN-1'},
                  },
                ],
              })
              as Map;
      expect(redacted['token'], mask);
      expect(redacted['refreshToken'], mask);
      expect(redacted['scope'], 'TENANT_ADMIN');
      final cred =
          ((redacted['devices'] as List).single as Map)['credentials'] as Map;
      expect(cred['credentialsId'], mask);
      expect(((redacted['devices'] as List).single as Map)['name'], 'Sensor');
    });

    test('never mutates its input', () {
      final original = {
        'password': 'pw',
        'nested': {'token': 't'},
      };
      TbNetworkRedactor.redactBody(original);
      expect(original['password'], 'pw');
      expect((original['nested'] as Map)['token'], 't');
    });

    test('keeps null and non-sensitive values untouched', () {
      final redacted =
          TbNetworkRedactor.redactBody({'password': null, 'name': 'n', 'n': 3})
              as Map;
      expect(redacted['password'], isNull);
      expect(redacted['name'], 'n');
      expect(redacted['n'], 3);
    });

    test(
      'masks inside a JSON string body and passes plain strings through',
      () {
        final json =
            TbNetworkRedactor.redactBody('{"password":"pw","user":"u"}')
                as String;
        expect(json, isNot(contains('pw')));
        expect(json, contains('"user":"u"'));
        expect(TbNetworkRedactor.redactBody('hello'), 'hello');
        expect(TbNetworkRedactor.redactBody(42), 42);
      },
    );
  });

  group('redactUrl', () {
    test('masks the 2FA verification code but keeps other parameters', () {
      final url = TbNetworkRedactor.redactUrl(
        'https://tb.example.com/api/auth/2fa/verification/check'
        '?providerType=TOTP&verificationCode=123456',
      );
      expect(url, isNot(contains('123456')));
      expect(url, contains('providerType=TOTP'));
      expect(url, contains('verificationCode='));
    });

    test('masks the QR login secret in the path', () {
      final url = TbNetworkRedactor.redactUrl(
        'https://tb.example.com/api/noauth/qr/super-secret-qr',
      );
      expect(url, isNot(contains('super-secret-qr')));
      expect(url, startsWith('https://tb.example.com/api/noauth/qr/'));
    });

    test('leaves ordinary URLs byte-for-byte unchanged', () {
      const url = 'https://tb.example.com/api/v2/alarms?page=0&pageSize=20';
      expect(TbNetworkRedactor.redactUrl(url), url);
    });
  });

  group('hardening: keys and shapes that must never leak', () {
    test(
      'any token/password/secret-like key is masked, not just a fixed list',
      () {
        final body =
            TbNetworkRedactor.redactBody({
                  'activateToken': 'S1',
                  'resetToken': 'S2',
                  'idToken': 'S3',
                  'pin': 'S4',
                  'emailCode': 'S5',
                  'smsCode': 'S6',
                  'clientSecret': 'S7',
                  'confirmPassword': 'S8',
                  'statusCode': 404, // not a secret
                  'errorCode': 31, // not a secret
                })
                as Map;
        for (final key in [
          'activateToken',
          'resetToken',
          'idToken',
          'pin',
          'emailCode',
          'smsCode',
          'clientSecret',
          'confirmPassword',
        ]) {
          expect(body[key], mask, reason: key);
        }
        expect(body['statusCode'], 404);
        expect(body['errorCode'], 31);
      },
    );

    test(
      'URL: activation/reset tokens and credentials in userinfo are masked',
      () {
        for (final url in [
          'https://tb.example.com/api/noauth/activate?activateToken=SECRET1',
          'https://tb.example.com/api/noauth/resetPassword?resetToken=SECRET1',
          'https://user:SECRET1@tb.example.com/api/auth/user',
        ]) {
          expect(
            TbNetworkRedactor.redactUrl(url),
            isNot(contains('SECRET1')),
            reason: url,
          );
        }
      },
    );

    test('free text: truncated or embedded JSON secrets are masked', () {
      final truncated = TbNetworkRedactor.redactText(
        '{"password":"SECRET1","user"',
      );
      expect(truncated, isNot(contains('SECRET1')));
      final embedded = TbNetworkRedactor.redactText(
        'failed with body {"refreshToken": "SECRET2", "ok": true}',
      );
      expect(embedded, isNot(contains('SECRET2')));
      expect(embedded, contains('"ok": true'));
    });

    test(
      'an invalid JSON string body is scrubbed instead of passed through',
      () {
        final out =
            TbNetworkRedactor.redactBody('{"password":"SECRET1" oops')
                as String;
        expect(out, isNot(contains('SECRET1')));
      },
    );
  });

  group('redactText and redactHeaders', () {
    test('scrubs secrets that appear inside error messages', () {
      final text = TbNetworkRedactor.redactText(
        'GET /api/noauth/qr/abc123 failed; ?verificationCode=999999&x=1',
      );
      expect(text, isNot(contains('abc123')));
      expect(text, isNot(contains('999999')));
      expect(text, contains('x=1'));
    });

    test('masks authorization, token and cookie headers only', () {
      final headers = TbNetworkRedactor.redactHeaders({
        'X-Authorization': 'Bearer jwt-1',
        'X-Mobile-Token': 'fcm-1',
        'Cookie': 'a=b',
        'Content-Type': 'application/json',
      });
      expect(headers['X-Authorization'], 'Bearer $mask');
      expect(headers['X-Mobile-Token'], mask);
      expect(headers['Cookie'], mask);
      expect(headers['Content-Type'], 'application/json');
    });
  });
}
