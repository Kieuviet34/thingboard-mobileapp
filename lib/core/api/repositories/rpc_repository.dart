import 'package:dio/dio.dart';
import 'package:thingsboard_democloud_app/core/api/client/tb_api_client.dart';
import 'package:thingsboard_democloud_app/core/mock/mock_data.dart';
import 'package:thingsboard_democloud_app/core/models/pagination.dart';
import 'package:thingsboard_democloud_app/core/models/tb_failure.dart';
import 'package:thingsboard_democloud_app/core/models/telemetry_models.dart';

/// Device RPC execution (one-way, two-way) and persistent RPC management boundary.
abstract interface class RpcRepository {
  Future<Map<String, dynamic>?> sendOneWayRpc(
    String deviceId,
    TbRpcRequest request, {
    CancelToken? cancelToken,
  });

  Future<Map<String, dynamic>?> sendTwoWayRpc(
    String deviceId,
    TbRpcRequest request, {
    CancelToken? cancelToken,
  });

  Future<PageData<TbPersistentRpc>> getPersistentRpcs(
    String deviceId,
    PageQuery query,
  );

  Future<void> deletePersistentRpc(String rpcId);
}

final class RestRpcRepository implements RpcRepository {
  RestRpcRepository({required TbApiClient client}) : _client = client;

  final TbApiClient _client;

  @override
  Future<Map<String, dynamic>?> sendOneWayRpc(
    String deviceId,
    TbRpcRequest request, {
    CancelToken? cancelToken,
  }) async {
    final response = await _client.post<dynamic>(
      '/api/rpc/oneway/$deviceId',
      data: request.toJson(),
      cancelToken: cancelToken,
    );
    return response.data is Map<String, dynamic>
        ? response.data as Map<String, dynamic>
        : null;
  }

  @override
  Future<Map<String, dynamic>?> sendTwoWayRpc(
    String deviceId,
    TbRpcRequest request, {
    CancelToken? cancelToken,
  }) async {
    final response = await _client.post<dynamic>(
      '/api/rpc/twoway/$deviceId',
      data: request.toJson(),
      cancelToken: cancelToken,
    );
    if (response.data is Map<String, dynamic>) {
      return response.data as Map<String, dynamic>;
    }
    if (response.data == null || response.data == '') return null;
    return <String, dynamic>{'result': response.data};
  }

  @override
  Future<PageData<TbPersistentRpc>> getPersistentRpcs(
    String deviceId,
    PageQuery query,
  ) async {
    final response = await _client.get<Map<String, dynamic>>(
      '/api/rpc/persistent/device/$deviceId',
      queryParameters: query.toQueryParameters(),
    );
    return PageData<TbPersistentRpc>.fromJson(
      response.data ?? const <String, dynamic>{},
      TbPersistentRpc.fromJson,
    );
  }

  @override
  Future<void> deletePersistentRpc(String rpcId) async {
    await _client.delete<void>('/api/rpc/persistent/$rpcId');
  }
}

final class DemoRpcRepository implements RpcRepository {
  DemoRpcRepository(List<MockDevice> devices)
    : _devices = devices,
      _rpcs = {
        for (final entry in demoPersistentRpcs.entries)
          entry.key: List<TbPersistentRpc>.from(entry.value),
      };

  final List<MockDevice> _devices;
  final Map<String, List<TbPersistentRpc>> _rpcs;

  @override
  Future<Map<String, dynamic>?> sendOneWayRpc(
    String deviceId,
    TbRpcRequest request, {
    CancelToken? cancelToken,
  }) async {
    return _executeDemoRpc(deviceId, request, twoWay: false);
  }

  @override
  Future<Map<String, dynamic>?> sendTwoWayRpc(
    String deviceId,
    TbRpcRequest request, {
    CancelToken? cancelToken,
  }) async {
    return _executeDemoRpc(deviceId, request, twoWay: true);
  }

  Future<Map<String, dynamic>?> _executeDemoRpc(
    String deviceId,
    TbRpcRequest request, {
    required bool twoWay,
  }) async {
    final device = _devices.where((d) => d.id == deviceId).firstOrNull;
    if (device == null) {
      throw const TbFailure(
        type: TbFailureType.notFound,
        statusCode: 404,
        message: 'Device not found',
      );
    }

    if (request.persistent) {
      final rpcId = 'rpc-${DateTime.now().millisecondsSinceEpoch}';
      _rpcs
          .putIfAbsent(deviceId, () => [])
          .insert(
            0,
            TbPersistentRpc(
              id: rpcId,
              deviceId: deviceId,
              createdTime: DateTime.now().millisecondsSinceEpoch,
              status: device.active ? RpcStatus.successful : RpcStatus.queued,
              request: request.toJson(),
              response: device.active ? const {'status': 'OK'} : null,
            ),
          );
      return <String, dynamic>{'rpcId': rpcId};
    }

    if (!device.active) {
      throw TbFailure(
        type: TbFailureType.deviceOfflineOrTimeout,
        statusCode: 504,
        message: 'Device ${device.name} is offline (RPC timeout)',
      );
    }

    if (!twoWay) return null;
    return <String, dynamic>{
      'method': request.method,
      'status': 'OK',
      'echo': request.params,
    };
  }

  @override
  Future<PageData<TbPersistentRpc>> getPersistentRpcs(
    String deviceId,
    PageQuery query,
  ) async {
    final list = _rpcs[deviceId] ?? const <TbPersistentRpc>[];
    return PageData<TbPersistentRpc>(
      data: List<TbPersistentRpc>.unmodifiable(list),
      totalPages: 1,
      totalElements: list.length,
      hasNext: false,
    );
  }

  @override
  Future<void> deletePersistentRpc(String rpcId) async {
    for (final list in _rpcs.values) {
      list.removeWhere((r) => r.id == rpcId);
    }
  }
}
