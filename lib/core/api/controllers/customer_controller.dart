import 'package:dio/dio.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:thingsboard_democloud_app/core/api/controllers/server_config_controller.dart';
import 'package:thingsboard_democloud_app/core/api/repositories/customer_repository.dart';
import 'package:thingsboard_democloud_app/core/mock/mock_data.dart';
import 'package:thingsboard_democloud_app/core/models/auth_models.dart';
import 'package:thingsboard_democloud_app/core/models/customer_models.dart';
import 'package:thingsboard_democloud_app/core/models/pagination.dart';
import 'package:thingsboard_democloud_app/core/models/tb_failure.dart';

final customerRepositoryProvider = Provider<CustomerRepository>((ref) {
  final sessionScope = ref.watch(
    serverConfigProvider.select((s) => (s.mode, s.sessionGeneration)),
  );
  if (sessionScope.$1 == SessionMode.demo) {
    return DemoCustomerRepository(ref.read(customersProvider));
  }
  return RestCustomerRepository(client: ref.watch(tbApiClientProvider));
});

/// Paginated customers list controller with `_requestSeq` + `CancelToken` race guard.
class CustomersNotifier
    extends
        AutoDisposeFamilyAsyncNotifier<
          PagedListState<TbCustomerInfo>,
          String?
        > {
  int _requestSeq = 0;
  CancelToken? _activeCancelToken;

  @override
  Future<PagedListState<TbCustomerInfo>> build(String? arg) async {
    ref.onDispose(() => _activeCancelToken?.cancel('Disposed'));
    return _fetchPage(page: 0, textSearch: arg, existing: const []);
  }

  Future<void> refresh() async {
    state = const AsyncLoading<PagedListState<TbCustomerInfo>>();
    state = await AsyncValue.guard(
      () => _fetchPage(page: 0, textSearch: arg, existing: const []),
    );
  }

  Future<void> loadNextPage() async {
    final current = state.valueOrNull;
    if (current == null || !current.hasNext || current.isLoadingMore) return;

    state = AsyncData(
      current.copyWith(isLoadingMore: true, clearLoadMoreError: true),
    );
    try {
      final nextState = await _fetchPage(
        page: current.page + 1,
        textSearch: arg,
        existing: current.items,
      );
      state = AsyncData(nextState);
    } on TbFailure catch (e) {
      if (e.isCancelled) return;
      state = AsyncData(
        current.copyWith(isLoadingMore: false, loadMoreError: e),
      );
    }
  }

  Future<PagedListState<TbCustomerInfo>> _fetchPage({
    required int page,
    required String? textSearch,
    required List<TbCustomerInfo> existing,
  }) async {
    final seq = ++_requestSeq;
    _activeCancelToken?.cancel('Superseded by newer customer query');
    final cancelToken = CancelToken();
    _activeCancelToken = cancelToken;

    final client = ref.read(tbApiClientProvider);
    final gen = client.sessionGeneration;

    final result = await ref
        .read(customerRepositoryProvider)
        .getCustomers(
          PageQuery(page: page, pageSize: 20, textSearch: textSearch),
          cancelToken: cancelToken,
        );

    if (seq != _requestSeq || gen != client.sessionGeneration) {
      throw const TbFailure(
        type: TbFailureType.cancelled,
        message: 'Stale customer response discarded',
      );
    }

    return PagedListState<TbCustomerInfo>(
      items: page == 0 ? result.data : [...existing, ...result.data],
      page: page,
      hasNext: result.hasNext,
      totalElements: result.totalElements,
    );
  }
}

final customersListProvider = AsyncNotifierProvider.autoDispose
    .family<CustomersNotifier, PagedListState<TbCustomerInfo>, String?>(
      CustomersNotifier.new,
    );

final customerDetailsProvider = FutureProvider.autoDispose
    .family<TbCustomerInfo, String>((ref, id) {
      return ref.watch(customerRepositoryProvider).getCustomerInfo(id);
    });
