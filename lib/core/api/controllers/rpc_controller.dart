import 'package:dio/dio.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:thingsboard_democloud_app/core/api/controllers/server_config_controller.dart';
import 'package:thingsboard_democloud_app/core/api/repositories/rpc_repository.dart';
import 'package:thingsboard_democloud_app/core/mock/mock_data.dart';
import 'package:thingsboard_democloud_app/core/models/auth_models.dart';
import 'package:thingsboard_democloud_app/core/models/pagination.dart';
import 'package:thingsboard_democloud_app/core/models/tb_failure.dart';
import 'package:thingsboard_democloud_app/core/models/telemetry_models.dart';

final rpcRepositoryProvider = Provider<RpcRepository>((ref) {
  final sessionScope = ref.watch(
    serverConfigProvider.select((s) => (s.mode, s.sessionGeneration)),
  );
  if (sessionScope.$1 == SessionMode.demo) {
    return DemoRpcRepository(ref.read(devicesProvider));
  }
  return RestRpcRepository(client: ref.watch(tbApiClientProvider));
});

/// Device-scoped RPC executor cancelling in-flight commands on dispose or device switch.
class RpcNotifier
    extends AutoDisposeFamilyAsyncNotifier<Map<String, dynamic>?, String> {
  int _requestSeq = 0;
  CancelToken? _activeCancelToken;

  @override
  Future<Map<String, dynamic>?> build(String arg) async {
    ref.onDispose(() {
      _requestSeq++;
      _activeCancelToken?.cancel('RPC view disposed');
    });
    return null;
  }

  Future<void> execute({
    required TbRpcRequest request,
    required bool twoWay,
  }) async {
    final seq = ++_requestSeq;
    _activeCancelToken?.cancel('Superseded by newer RPC request');
    final cancelToken = CancelToken();
    _activeCancelToken = cancelToken;

    final client = ref.read(tbApiClientProvider);
    final gen = client.sessionGeneration;

    state = const AsyncLoading<Map<String, dynamic>?>();
    try {
      final repo = ref.read(rpcRepositoryProvider);
      final result = twoWay
          ? await repo.sendTwoWayRpc(arg, request, cancelToken: cancelToken)
          : await repo.sendOneWayRpc(arg, request, cancelToken: cancelToken);

      if (seq != _requestSeq || gen != client.sessionGeneration) return;
      state = AsyncData<Map<String, dynamic>?>(result);
      if (request.persistent) {
        ref.invalidate(persistentRpcsProvider(arg));
      }
    } catch (error, stackTrace) {
      if (seq != _requestSeq || gen != client.sessionGeneration) return;
      if (error is TbFailure && error.isCancelled) return;
      state = AsyncError<Map<String, dynamic>?>(error, stackTrace);
    }
  }
}

final rpcControllerProvider = AsyncNotifierProvider.autoDispose
    .family<RpcNotifier, Map<String, dynamic>?, String>(RpcNotifier.new);

class PersistentRpcsNotifier
    extends
        AutoDisposeFamilyAsyncNotifier<
          PagedListState<TbPersistentRpc>,
          String
        > {
  @override
  Future<PagedListState<TbPersistentRpc>> build(String arg) async {
    final page = await ref
        .watch(rpcRepositoryProvider)
        .getPersistentRpcs(arg, const PageQuery(pageSize: 20));
    return PagedListState<TbPersistentRpc>(
      items: page.data,
      hasNext: page.hasNext,
      totalElements: page.totalElements,
    );
  }

  Future<void> deleteRpc(String rpcId) async {
    await ref.read(rpcRepositoryProvider).deletePersistentRpc(rpcId);
    final current = state.valueOrNull;
    if (current != null) {
      state = AsyncData(
        current.copyWith(
          items: current.items.where((r) => r.id != rpcId).toList(),
          totalElements: (current.totalElements - 1).clamp(0, 1 << 30),
        ),
      );
    }
  }
}

final persistentRpcsProvider = AsyncNotifierProvider.autoDispose
    .family<PersistentRpcsNotifier, PagedListState<TbPersistentRpc>, String>(
      PersistentRpcsNotifier.new,
    );
