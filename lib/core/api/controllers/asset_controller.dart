import 'package:dio/dio.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:thingsboard_democloud_app/core/api/controllers/auth_controller.dart';
import 'package:thingsboard_democloud_app/core/api/controllers/server_config_controller.dart';
import 'package:thingsboard_democloud_app/core/api/repositories/asset_repository.dart';
import 'package:thingsboard_democloud_app/core/mock/mock_data.dart';
import 'package:thingsboard_democloud_app/core/models/asset_models.dart';
import 'package:thingsboard_democloud_app/core/models/auth_models.dart';
import 'package:thingsboard_democloud_app/core/models/entity_id.dart';
import 'package:thingsboard_democloud_app/core/models/pagination.dart';
import 'package:thingsboard_democloud_app/core/models/tb_failure.dart';

final assetRepositoryProvider = Provider<AssetRepository>((ref) {
  final sessionScope = ref.watch(
    serverConfigProvider.select((s) => (s.mode, s.sessionGeneration)),
  );
  if (sessionScope.$1 == SessionMode.demo) {
    return DemoAssetRepository(ref.read(assetsProvider));
  }
  return RestAssetRepository(
    client: ref.watch(tbApiClientProvider),
    userScopeProvider: () {
      final authState = ref.read(authProvider).valueOrNull;
      final session = authState is AuthAuthenticated ? authState.session : null;
      return (authority: session?.authority, customerId: session?.customerId);
    },
  );
});

/// Paginated assets list controller with `_requestSeq` + `CancelToken` race guard.
class AssetsNotifier
    extends
        AutoDisposeFamilyAsyncNotifier<
          PagedListState<TbAssetInfo>,
          TbAssetQuery
        > {
  int _requestSeq = 0;
  CancelToken? _activeCancelToken;

  @override
  Future<PagedListState<TbAssetInfo>> build(TbAssetQuery arg) async {
    ref.onDispose(() => _activeCancelToken?.cancel('Disposed'));
    return _fetchPage(page: 0, filter: arg, existing: const []);
  }

  Future<void> refresh() async {
    state = const AsyncLoading<PagedListState<TbAssetInfo>>();
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

  Future<PagedListState<TbAssetInfo>> _fetchPage({
    required int page,
    required TbAssetQuery filter,
    required List<TbAssetInfo> existing,
  }) async {
    final seq = ++_requestSeq;
    _activeCancelToken?.cancel('Superseded by newer asset query');
    final cancelToken = CancelToken();
    _activeCancelToken = cancelToken;

    final client = ref.read(tbApiClientProvider);
    final gen = client.sessionGeneration;

    final result = await ref
        .read(assetRepositoryProvider)
        .getAssets(
          PageQuery(page: page, pageSize: 20, textSearch: filter.textSearch),
          filter,
          cancelToken: cancelToken,
        );

    if (seq != _requestSeq || gen != client.sessionGeneration) {
      throw const TbFailure(
        type: TbFailureType.cancelled,
        message: 'Stale asset response discarded',
      );
    }

    return PagedListState<TbAssetInfo>(
      items: page == 0 ? result.data : [...existing, ...result.data],
      page: page,
      hasNext: result.hasNext,
      totalElements: result.totalElements,
    );
  }
}

final assetsListProvider = AsyncNotifierProvider.autoDispose
    .family<AssetsNotifier, PagedListState<TbAssetInfo>, TbAssetQuery>(
      AssetsNotifier.new,
    );

final assetDetailsProvider = FutureProvider.autoDispose
    .family<TbAssetInfo, String>((ref, id) {
      return ref.watch(assetRepositoryProvider).getAssetInfo(id);
    });

final assetProfilesProvider =
    FutureProvider.autoDispose<List<TbAssetProfileInfo>>((ref) async {
      final page = await ref
          .watch(assetRepositoryProvider)
          .getAssetProfiles(const PageQuery(pageSize: 50));
      return page.data;
    });

final entityRelationsProvider = FutureProvider.autoDispose
    .family<List<TbEntityRelationInfo>, ({EntityId entity, bool outgoing})>((
      ref,
      params,
    ) {
      return ref
          .watch(assetRepositoryProvider)
          .getRelations(params.entity, outgoing: params.outgoing);
    });
