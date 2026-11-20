import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thingsboard_democloud_app/core/api/client/tb_error_mapper.dart';
import 'package:thingsboard_democloud_app/core/models/tb_failure.dart';

DioException _dioResponseError({
  required int statusCode,
  Map<String, dynamic>? data,
}) {
  final options = RequestOptions(path: '/api/test');
  return DioException(
    requestOptions: options,
    type: DioExceptionType.badResponse,
    response: Response<dynamic>(
      requestOptions: options,
      statusCode: statusCode,
      data: data,
    ),
  );
}

void main() {
  group('TbErrorMapper', () {
    test('maps all documented ThingsboardErrorCode integers accurately', () {
      const expected = <int, TbFailureType>{
        2: TbFailureType.serverError,
        10: TbFailureType.invalidCredentials,
        11: TbFailureType.tokenExpired,
        12: TbFailureType.tokenExpired,
        15: TbFailureType.passwordExpired,
        20: TbFailureType.permissionDenied,
        30: TbFailureType.validation,
        31: TbFailureType.validation,
        32: TbFailureType.notFound,
        33: TbFailureType.rateLimited,
        34: TbFailureType.rateLimited,
        35: TbFailureType.conflict,
        40: TbFailureType.quotaExceeded,
        41: TbFailureType.quotaExceeded,
        45: TbFailureType.passwordPolicy,
        46: TbFailureType.serverError,
        47: TbFailureType.serverError,
        50: TbFailureType.serverError,
      };

      for (final entry in expected.entries) {
        final failure = TbErrorMapper.fromException(
          _dioResponseError(
            statusCode: 400,
            data: <String, dynamic>{
              'errorCode': entry.key,
              'status': 400,
              'message': 'err-${entry.key}',
              if (entry.key == 40) 'subscriptionErrorCode': 2,
            },
          ),
        );
        expect(
          failure.type,
          entry.value,
          reason: 'errorCode ${entry.key} should map to ${entry.value}',
        );
        expect(failure.errorCode, entry.key);
        if (entry.key == 40) {
          expect(failure.subscriptionErrorCode, 2);
        }
      }
    });

    test('does not confuse errorCode 40 with versionConflict 35', () {
      final failure = TbErrorMapper.fromException(
        _dioResponseError(
          statusCode: 403,
          data: <String, dynamic>{
            'errorCode': 40,
            'status': 403,
            'message': 'Subscription violation',
            'subscriptionErrorCode': 3,
          },
        ),
      );
      expect(failure.type, TbFailureType.quotaExceeded);
      expect(failure.type, isNot(TbFailureType.conflict));
    });

    test(
      'maps HTTP 504 RPC timeout, 406 invalid RPC reply, 403, and 404 without body',
      () {
        expect(
          TbErrorMapper.fromException(_dioResponseError(statusCode: 504)).type,
          TbFailureType.deviceOfflineOrTimeout,
        );
        expect(
          TbErrorMapper.fromException(_dioResponseError(statusCode: 406)).type,
          TbFailureType.invalidDeviceRpcReply,
        );
        expect(
          TbErrorMapper.fromException(_dioResponseError(statusCode: 403)).type,
          TbFailureType.permissionDenied,
        );
        expect(
          TbErrorMapper.fromException(_dioResponseError(statusCode: 404)).type,
          TbFailureType.notFound,
        );
      },
    );

    test(
      'maps network timeouts, connection errors, and CancelToken cancellations',
      () {
        final options = RequestOptions(path: '/api/devices');
        expect(
          TbErrorMapper.fromException(
            DioException(
              requestOptions: options,
              type: DioExceptionType.connectionError,
            ),
          ).type,
          TbFailureType.networkUnavailable,
        );
        expect(
          TbErrorMapper.fromException(
            DioException(
              requestOptions: options,
              type: DioExceptionType.receiveTimeout,
            ),
          ).type,
          TbFailureType.networkUnavailable,
        );
        expect(
          TbErrorMapper.fromException(
            DioException(
              requestOptions: options,
              type: DioExceptionType.cancel,
            ),
          ).type,
          TbFailureType.cancelled,
        );
      },
    );
  });
}
