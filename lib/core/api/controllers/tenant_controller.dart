import 'package:dio/dio.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:thingsboard_democloud_app/core/api/controllers/auth_controller.dart';
import 'package:thingsboard_democloud_app/core/api/controllers/server_config_controller.dart';
import 'package:thingsboard_democloud_app/core/api/repositories/tenant_repository.dart';
import 'package:thingsboard_democloud_app/core/models/auth_models.dart';
import 'package:thingsboard_democloud_app/core/models/dashboard_models.dart';
import 'package:thingsboard_democloud_app/core/models/entity_id.dart';
import 'package:thingsboard_democloud_app/core/models/pagination.dart';
import 'package:thingsboard_democloud_app/core/models/tb_failure.dart';
import 'package:thingsboard_democloud_app/core/models/tenant_models.dart';
import 'package:thingsboard_democloud_app/core/models/user_models.dart';

final tenantRepositoryProvider = Provider<TenantRepository>((ref) {
  final sessionScope = ref.watch(
    serverConfigProvider.select((s) => (s.mode, s.sessionGeneration)),
  );
  if (sessionScope.$1 == SessionMode.demo) {
    return DemoTenantRepository();
  }
  return RestTenantRepository(client: ref.watch(tbApiClientProvider));
});

/// Resolves the active session's `tenantId` (falling back to `'demo-tenant-1'` in Demo mode).
final activeTenantIdProvider = Provider<String?>((ref) {
  final authState = ref.watch(authProvider).valueOrNull;
  if (authState is AuthAuthenticated) {
    final tid = authState.user.tenantId ?? authState.session.tenantId;
    if (tid != null && tid.isNotEmpty) return tid;
    if (authState.mode == SessionMode.demo) return 'demo-tenant-1';
  }
  final mode = ref.watch(serverConfigProvider.select((s) => s.mode));
  if (mode == SessionMode.demo) return 'demo-tenant-1';
  return null;
});

/// Current tenant detail (`TENANT_ADMIN`) with save support.
class CurrentTenantController extends AutoDisposeAsyncNotifier<TbTenantInfo?> {
  @override
  Future<TbTenantInfo?> build() async {
    final tenantId = ref.watch(activeTenantIdProvider);
    if (tenantId == null || tenantId.isEmpty) return null;
    return ref.watch(tenantRepositoryProvider).getTenantInfo(tenantId);
  }

  Future<TbTenantInfo> save(TbTenantInfo updated) async {
    final saved = await ref.read(tenantRepositoryProvider).saveTenant(updated);
    state = AsyncData<TbTenantInfo?>(saved);
    return saved;
  }
}

final currentTenantInfoProvider =
    AsyncNotifierProvider.autoDispose<CurrentTenantController, TbTenantInfo?>(
      CurrentTenantController.new,
    );

final tenantDetailsProvider = FutureProvider.autoDispose
    .family<TbTenantInfo, String>((ref, tenantId) {
      return ref.watch(tenantRepositoryProvider).getTenantInfo(tenantId);
    });

final defaultTenantProfileProvider =
    FutureProvider.autoDispose<TbTenantProfileInfo?>((ref) {
      return ref.watch(tenantRepositoryProvider).getDefaultTenantProfileInfo();
    });

final tenantSubscriptionSummaryProvider =
    FutureProvider.autoDispose<TbTenantSubscriptionSummary?>((ref) {
      return ref.watch(tenantRepositoryProvider).getSubscriptionSummary();
    });

final tenantHomeDashboardProvider =
    FutureProvider.autoDispose<TbHomeDashboardInfo?>((ref) {
      return ref.watch(tenantRepositoryProvider).getTenantHomeDashboardInfo();
    });

/// Paginated `SYS_ADMIN` tenants list controller (`/api/tenantInfos` -> `/api/tenants`).
class TenantsNotifier
    extends
        AutoDisposeFamilyAsyncNotifier<PagedListState<TbTenantInfo>, String?> {
  int _requestSeq = 0;
  CancelToken? _activeCancelToken;

  @override
  Future<PagedListState<TbTenantInfo>> build(String? arg) async {
    ref.onDispose(() => _activeCancelToken?.cancel('Disposed'));
    return _fetchPage(page: 0, textSearch: arg, existing: const []);
  }

  Future<void> refresh() async {
    state = const AsyncLoading<PagedListState<TbTenantInfo>>();
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

  Future<TbTenantInfo> saveTenant(TbTenantInfo tenant) async {
    final saved = await ref.read(tenantRepositoryProvider).saveTenant(tenant);
    await refresh();
    return saved;
  }

  Future<void> deleteTenant(String tenantId) async {
    await ref.read(tenantRepositoryProvider).deleteTenant(tenantId);
    await refresh();
  }

  Future<PagedListState<TbTenantInfo>> _fetchPage({
    required int page,
    required String? textSearch,
    required List<TbTenantInfo> existing,
  }) async {
    final seq = ++_requestSeq;
    _activeCancelToken?.cancel('Superseded by newer tenants query');
    final cancelToken = CancelToken();
    _activeCancelToken = cancelToken;

    final client = ref.read(tbApiClientProvider);
    final gen = client.sessionGeneration;

    final result = await ref
        .read(tenantRepositoryProvider)
        .getTenantInfos(
          PageQuery(page: page, pageSize: 20, textSearch: textSearch),
          cancelToken: cancelToken,
        );

    if (seq != _requestSeq || gen != client.sessionGeneration) {
      throw const TbFailure(
        type: TbFailureType.cancelled,
        message: 'Stale tenants response discarded',
      );
    }

    return PagedListState<TbTenantInfo>(
      items: page == 0 ? result.data : [...existing, ...result.data],
      page: page,
      hasNext: result.hasNext,
      totalElements: result.totalElements,
    );
  }
}

final tenantsListProvider = AsyncNotifierProvider.autoDispose
    .family<TenantsNotifier, PagedListState<TbTenantInfo>, String?>(
      TenantsNotifier.new,
    );

/// Paginated `SYS_ADMIN` tenant profiles controller (`/api/tenantProfileInfos`).
class TenantProfilesNotifier
    extends
        AutoDisposeFamilyAsyncNotifier<
          PagedListState<TbTenantProfileInfo>,
          String?
        > {
  int _requestSeq = 0;
  CancelToken? _activeCancelToken;

  @override
  Future<PagedListState<TbTenantProfileInfo>> build(String? arg) async {
    ref.onDispose(() => _activeCancelToken?.cancel('Disposed'));
    return _fetchPage(page: 0, textSearch: arg, existing: const []);
  }

  Future<void> refresh() async {
    state = const AsyncLoading<PagedListState<TbTenantProfileInfo>>();
    state = await AsyncValue.guard(
      () => _fetchPage(page: 0, textSearch: arg, existing: const []),
    );
  }

  Future<void> setDefault(String profileId) async {
    await ref.read(tenantRepositoryProvider).setDefaultTenantProfile(profileId);
    await refresh();
  }

  Future<PagedListState<TbTenantProfileInfo>> _fetchPage({
    required int page,
    required String? textSearch,
    required List<TbTenantProfileInfo> existing,
  }) async {
    final seq = ++_requestSeq;
    _activeCancelToken?.cancel('Superseded by newer tenant profiles query');
    final cancelToken = CancelToken();
    _activeCancelToken = cancelToken;

    final client = ref.read(tbApiClientProvider);
    final gen = client.sessionGeneration;

    final result = await ref
        .read(tenantRepositoryProvider)
        .getTenantProfileInfos(
          PageQuery(page: page, pageSize: 20, textSearch: textSearch),
          cancelToken: cancelToken,
        );

    if (seq != _requestSeq || gen != client.sessionGeneration) {
      throw const TbFailure(
        type: TbFailureType.cancelled,
        message: 'Stale tenant profiles response discarded',
      );
    }

    return PagedListState<TbTenantProfileInfo>(
      items: page == 0 ? result.data : [...existing, ...result.data],
      page: page,
      hasNext: result.hasNext,
      totalElements: result.totalElements,
    );
  }
}

final tenantProfilesListProvider = AsyncNotifierProvider.autoDispose
    .family<
      TenantProfilesNotifier,
      PagedListState<TbTenantProfileInfo>,
      String?
    >(TenantProfilesNotifier.new);

/// Paginated `TENANT_ADMIN` Entity Views controller (`/api/tenant/entityViewInfos` -> `/api/tenant/entityViews`).
class TenantEntityViewsNotifier
    extends
        AutoDisposeFamilyAsyncNotifier<
          PagedListState<TbEntityViewInfo>,
          String?
        > {
  int _requestSeq = 0;
  CancelToken? _activeCancelToken;

  @override
  Future<PagedListState<TbEntityViewInfo>> build(String? arg) async {
    ref.onDispose(() => _activeCancelToken?.cancel('Disposed'));
    return _fetchPage(page: 0, textSearch: arg, existing: const []);
  }

  Future<void> refresh() async {
    state = const AsyncLoading<PagedListState<TbEntityViewInfo>>();
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

  Future<PagedListState<TbEntityViewInfo>> _fetchPage({
    required int page,
    required String? textSearch,
    required List<TbEntityViewInfo> existing,
  }) async {
    final seq = ++_requestSeq;
    _activeCancelToken?.cancel('Superseded by newer entity views query');
    final cancelToken = CancelToken();
    _activeCancelToken = cancelToken;

    final client = ref.read(tbApiClientProvider);
    final gen = client.sessionGeneration;

    final result = await ref
        .read(tenantRepositoryProvider)
        .getTenantEntityViews(
          PageQuery(page: page, pageSize: 20, textSearch: textSearch),
          cancelToken: cancelToken,
        );

    if (seq != _requestSeq || gen != client.sessionGeneration) {
      throw const TbFailure(
        type: TbFailureType.cancelled,
        message: 'Stale entity views response discarded',
      );
    }

    return PagedListState<TbEntityViewInfo>(
      items: page == 0 ? result.data : [...existing, ...result.data],
      page: page,
      hasNext: result.hasNext,
      totalElements: result.totalElements,
    );
  }
}

final tenantEntityViewsProvider = AsyncNotifierProvider.autoDispose
    .family<
      TenantEntityViewsNotifier,
      PagedListState<TbEntityViewInfo>,
      String?
    >(TenantEntityViewsNotifier.new);

/// Paginated `TENANT_ADMIN` Edges controller (`/api/tenant/edgeInfos` -> `/api/tenant/edges`).
class TenantEdgesNotifier
    extends
        AutoDisposeFamilyAsyncNotifier<PagedListState<TbEdgeInfo>, String?> {
  int _requestSeq = 0;
  CancelToken? _activeCancelToken;

  @override
  Future<PagedListState<TbEdgeInfo>> build(String? arg) async {
    ref.onDispose(() => _activeCancelToken?.cancel('Disposed'));
    return _fetchPage(page: 0, textSearch: arg, existing: const []);
  }

  Future<void> refresh() async {
    state = const AsyncLoading<PagedListState<TbEdgeInfo>>();
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

  Future<PagedListState<TbEdgeInfo>> _fetchPage({
    required int page,
    required String? textSearch,
    required List<TbEdgeInfo> existing,
  }) async {
    final seq = ++_requestSeq;
    _activeCancelToken?.cancel('Superseded by newer edges query');
    final cancelToken = CancelToken();
    _activeCancelToken = cancelToken;

    final client = ref.read(tbApiClientProvider);
    final gen = client.sessionGeneration;

    final result = await ref
        .read(tenantRepositoryProvider)
        .getTenantEdges(
          PageQuery(page: page, pageSize: 20, textSearch: textSearch),
          cancelToken: cancelToken,
        );

    if (seq != _requestSeq || gen != client.sessionGeneration) {
      throw const TbFailure(
        type: TbFailureType.cancelled,
        message: 'Stale edges response discarded',
      );
    }

    return PagedListState<TbEdgeInfo>(
      items: page == 0 ? result.data : [...existing, ...result.data],
      page: page,
      hasNext: result.hasNext,
      totalElements: result.totalElements,
    );
  }
}

final tenantEdgesProvider = AsyncNotifierProvider.autoDispose
    .family<TenantEdgesNotifier, PagedListState<TbEdgeInfo>, String?>(
      TenantEdgesNotifier.new,
    );

final tenantUsersProvider = FutureProvider.autoDispose
    .family<PageData<TbUserProfile>, ({String tenantId, String? search})>((
      ref,
      arg,
    ) {
      return ref
          .watch(tenantRepositoryProvider)
          .getTenantUsers(
            arg.tenantId,
            PageQuery(page: 0, pageSize: 20, textSearch: arg.search),
          );
    });

/// Helper reporting whether [authority] can access Tenant workspace routes.
bool canAccessTenantWorkspace(Authority authority) =>
    authority == Authority.tenantAdmin || authority == Authority.sysAdmin;
