import 'package:dio/dio.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:thingsboard_democloud_app/core/api/controllers/auth_controller.dart';
import 'package:thingsboard_democloud_app/core/api/controllers/server_config_controller.dart';
import 'package:thingsboard_democloud_app/core/api/repositories/dashboard_repository.dart';
import 'package:thingsboard_democloud_app/core/mock/mock_data.dart';
import 'package:thingsboard_democloud_app/core/models/auth_models.dart';
import 'package:thingsboard_democloud_app/core/models/dashboard_models.dart';
import 'package:thingsboard_democloud_app/core/models/pagination.dart';
import 'package:thingsboard_democloud_app/core/models/tb_failure.dart';

final dashboardRepositoryProvider = Provider<DashboardRepository>((ref) {
  final sessionScope = ref.watch(
    serverConfigProvider.select((s) => (s.mode, s.sessionGeneration)),
  );
  if (sessionScope.$1 == SessionMode.demo) {
    return DemoDashboardRepository(ref.read(dashboardsProvider));
  }
  return RestDashboardRepository(client: ref.watch(tbApiClientProvider));
});

/// Paginated dashboards list controller with `_requestSeq` + `CancelToken` race guard.
class DashboardsNotifier
    extends
        AutoDisposeFamilyAsyncNotifier<
          PagedListState<TbDashboardInfo>,
          String?
        > {
  int _requestSeq = 0;
  CancelToken? _activeCancelToken;

  @override
  Future<PagedListState<TbDashboardInfo>> build(String? arg) async {
    ref.onDispose(() => _activeCancelToken?.cancel('Disposed'));
    return _fetchPage(page: 0, textSearch: arg, existing: const []);
  }

  Future<void> refresh() async {
    state = const AsyncLoading<PagedListState<TbDashboardInfo>>();
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

  Future<void> toggleStar(String dashboardId) async {
    final current = state.valueOrNull;
    if (current == null) return;
    final idx = current.items.indexWhere((d) => d.id == dashboardId);
    if (idx == -1) return;

    final target = current.items[idx];
    final nextStarred = !target.isStarred;
    final updatedItems = List<TbDashboardInfo>.from(current.items);
    updatedItems[idx] = target.copyWith(isStarred: nextStarred);
    state = AsyncData(current.copyWith(items: updatedItems));

    try {
      await ref
          .read(dashboardRepositoryProvider)
          .reportDashboardAction(dashboardId, nextStarred ? 'STAR' : 'UNSTAR');
      ref.invalidate(userDashboardsInfoProvider);
    } catch (_) {
      // Rollback on failure.
      state = AsyncData(current);
      rethrow;
    }
  }

  Future<PagedListState<TbDashboardInfo>> _fetchPage({
    required int page,
    required String? textSearch,
    required List<TbDashboardInfo> existing,
  }) async {
    final seq = ++_requestSeq;
    _activeCancelToken?.cancel('Superseded by newer dashboard query');
    final cancelToken = CancelToken();
    _activeCancelToken = cancelToken;

    final client = ref.read(tbApiClientProvider);
    final gen = client.sessionGeneration;
    final authState = ref.read(authProvider).valueOrNull;
    final session = authState is AuthAuthenticated ? authState.session : null;

    final result = await ref
        .read(dashboardRepositoryProvider)
        .getDashboards(
          PageQuery(page: page, pageSize: 20, textSearch: textSearch),
          authority: session?.authority,
          customerId: session?.customerId,
          cancelToken: cancelToken,
        );

    if (seq != _requestSeq || gen != client.sessionGeneration) {
      throw const TbFailure(
        type: TbFailureType.cancelled,
        message: 'Stale dashboard response discarded',
      );
    }

    return PagedListState<TbDashboardInfo>(
      items: page == 0 ? result.data : [...existing, ...result.data],
      page: page,
      hasNext: result.hasNext,
      totalElements: result.totalElements,
    );
  }
}

final dashboardsListProvider = AsyncNotifierProvider.autoDispose
    .family<DashboardsNotifier, PagedListState<TbDashboardInfo>, String?>(
      DashboardsNotifier.new,
    );

final homeDashboardProvider = FutureProvider.autoDispose<TbHomeDashboardInfo?>((
  ref,
) {
  return ref.watch(dashboardRepositoryProvider).getHomeDashboardInfo();
});

final userDashboardsInfoProvider =
    FutureProvider.autoDispose<UserDashboardsInfo>((ref) {
      return ref.watch(dashboardRepositoryProvider).getLastVisitedDashboards();
    });

final dashboardDetailsProvider = FutureProvider.autoDispose
    .family<TbDashboard, String>((ref, id) async {
      final repo = ref.watch(dashboardRepositoryProvider);
      final dashboard = await repo.getDashboardById(id);
      return dashboard;
    });
