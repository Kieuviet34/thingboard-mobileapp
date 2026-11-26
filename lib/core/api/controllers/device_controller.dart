import 'package:dio/dio.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:thingsboard_democloud_app/core/api/controllers/auth_controller.dart';
import 'package:thingsboard_democloud_app/core/api/controllers/server_config_controller.dart';
import 'package:thingsboard_democloud_app/core/api/repositories/device_repository.dart';
import 'package:thingsboard_democloud_app/core/mock/mock_data.dart';
import 'package:thingsboard_democloud_app/core/models/auth_models.dart';
import 'package:thingsboard_democloud_app/core/models/device_models.dart';
import 'package:thingsboard_democloud_app/core/models/pagination.dart';
import 'package:thingsboard_democloud_app/core/models/tb_failure.dart';

final deviceRepositoryProvider = Provider<DeviceRepository>((ref) {
  final sessionScope = ref.watch(
    serverConfigProvider.select((s) => (s.mode, s.sessionGeneration)),
  );
  if (sessionScope.$1 == SessionMode.demo) {
    return DemoDeviceRepository(ref.read(devicesProvider));
  }
  return RestDeviceRepository(
    client: ref.watch(tbApiClientProvider),
    userScopeProvider: () {
      final authState = ref.read(authProvider).valueOrNull;
      final session = authState is AuthAuthenticated ? authState.session : null;
      return (authority: session?.authority, customerId: session?.customerId);
    },
  );
});

/// Paginated device profiles with active/inactive counts.
class DeviceProfilesNotifier
    extends AutoDisposeAsyncNotifier<PagedListState<TbDeviceProfileSummary>> {
  int _requestSeq = 0;
  CancelToken? _activeCancelToken;

  @override
  Future<PagedListState<TbDeviceProfileSummary>> build() async {
    ref.onDispose(() => _activeCancelToken?.cancel('Disposed'));
    return _fetchPage(page: 0, existing: const []);
  }

  Future<void> refresh() async {
    state = const AsyncLoading<PagedListState<TbDeviceProfileSummary>>();
    state = await AsyncValue.guard(
      () => _fetchPage(page: 0, existing: const []),
    );
  }

  Future<PagedListState<TbDeviceProfileSummary>> _fetchPage({
    required int page,
    required List<TbDeviceProfileSummary> existing,
  }) async {
    final seq = ++_requestSeq;
    _activeCancelToken?.cancel('Superseded by newer profile query');
    final cancelToken = CancelToken();
    _activeCancelToken = cancelToken;

    final client = ref.read(tbApiClientProvider);
    final gen = client.sessionGeneration;

    final result = await ref
        .read(deviceRepositoryProvider)
        .getDeviceProfiles(
          PageQuery(
            page: page,
            pageSize: 20,
            sortProperty: 'name',
            sortOrder: SortOrder.asc,
          ),
          cancelToken: cancelToken,
        );

    if (seq != _requestSeq || gen != client.sessionGeneration) {
      throw const TbFailure(
        type: TbFailureType.cancelled,
        message: 'Stale device profile response discarded',
      );
    }

    return PagedListState<TbDeviceProfileSummary>(
      items: page == 0 ? result.data : [...existing, ...result.data],
      page: page,
      hasNext: result.hasNext,
      totalElements: result.totalElements,
    );
  }
}

final deviceProfilesListProvider =
    AsyncNotifierProvider.autoDispose<
      DeviceProfilesNotifier,
      PagedListState<TbDeviceProfileSummary>
    >(DeviceProfilesNotifier.new);

/// Paginated devices list controller with `_requestSeq` + `CancelToken` race guard.
class DevicesNotifier
    extends
        AutoDisposeFamilyAsyncNotifier<
          PagedListState<TbDeviceInfo>,
          TbDeviceQuery
        > {
  int _requestSeq = 0;
  CancelToken? _activeCancelToken;

  @override
  Future<PagedListState<TbDeviceInfo>> build(TbDeviceQuery arg) async {
    ref.onDispose(() => _activeCancelToken?.cancel('Disposed'));
    return _fetchPage(page: 0, filter: arg, existing: const []);
  }

  Future<void> refresh() async {
    state = const AsyncLoading<PagedListState<TbDeviceInfo>>();
    state = await AsyncValue.guard(
      () => _fetchPage(page: 0, filter: arg, existing: const []),
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
        filter: arg,
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

  Future<PagedListState<TbDeviceInfo>> _fetchPage({
    required int page,
    required TbDeviceQuery filter,
    required List<TbDeviceInfo> existing,
  }) async {
    final seq = ++_requestSeq;
    _activeCancelToken?.cancel('Superseded by newer device query');
    final cancelToken = CancelToken();
    _activeCancelToken = cancelToken;

    final client = ref.read(tbApiClientProvider);
    final gen = client.sessionGeneration;

    final result = await ref
        .read(deviceRepositoryProvider)
        .getDevices(
          PageQuery(page: page, pageSize: 20, textSearch: filter.textSearch),
          filter,
          cancelToken: cancelToken,
        );

    if (seq != _requestSeq || gen != client.sessionGeneration) {
      throw const TbFailure(
        type: TbFailureType.cancelled,
        message: 'Stale device response discarded',
      );
    }

    return PagedListState<TbDeviceInfo>(
      items: page == 0 ? result.data : [...existing, ...result.data],
      page: page,
      hasNext: result.hasNext,
      totalElements: result.totalElements,
    );
  }
}

final devicesListProvider = AsyncNotifierProvider.autoDispose
    .family<DevicesNotifier, PagedListState<TbDeviceInfo>, TbDeviceQuery>(
      DevicesNotifier.new,
    );

final deviceDetailsProvider = FutureProvider.autoDispose
    .family<TbDeviceInfo, String>((ref, id) {
      return ref.watch(deviceRepositoryProvider).getDeviceInfo(id);
    });

final deviceCredentialsProvider = FutureProvider.autoDispose
    .family<TbDeviceCredentials, String>((ref, id) {
      return ref.watch(deviceRepositoryProvider).getDeviceCredentials(id);
    });
