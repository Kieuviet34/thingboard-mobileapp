import 'package:dio/dio.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:thingsboard_democloud_app/core/api/controllers/server_config_controller.dart';
import 'package:thingsboard_democloud_app/core/api/repositories/audit_log_repository.dart';
import 'package:thingsboard_democloud_app/core/mock/mock_data.dart';
import 'package:thingsboard_democloud_app/core/models/audit_log_models.dart';
import 'package:thingsboard_democloud_app/core/models/auth_models.dart';
import 'package:thingsboard_democloud_app/core/models/pagination.dart';
import 'package:thingsboard_democloud_app/core/models/tb_failure.dart';

final auditLogRepositoryProvider = Provider<AuditLogRepository>((ref) {
  final sessionScope = ref.watch(
    serverConfigProvider.select((s) => (s.mode, s.sessionGeneration)),
  );
  if (sessionScope.$1 == SessionMode.demo) {
    return DemoAuditLogRepository(ref.read(auditLogsProvider));
  }
  return RestAuditLogRepository(client: ref.watch(tbApiClientProvider));
});

/// Paginated audit logs controller with `_requestSeq` + `CancelToken` race guard.
class AuditLogsNotifier
    extends
        AutoDisposeFamilyAsyncNotifier<
          PagedListState<TbAuditLog>,
          TbAuditLogQuery
        > {
  int _requestSeq = 0;
  CancelToken? _activeCancelToken;

  @override
  Future<PagedListState<TbAuditLog>> build(TbAuditLogQuery arg) async {
    ref.onDispose(() => _activeCancelToken?.cancel('Disposed'));
    return _fetchPage(page: 0, filter: arg, existing: const []);
  }

  Future<void> refresh() async {
    state = const AsyncLoading<PagedListState<TbAuditLog>>();
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

  Future<PagedListState<TbAuditLog>> _fetchPage({
    required int page,
    required TbAuditLogQuery filter,
    required List<TbAuditLog> existing,
  }) async {
    final seq = ++_requestSeq;
    _activeCancelToken?.cancel('Superseded by newer audit log query');
    final cancelToken = CancelToken();
    _activeCancelToken = cancelToken;

    final client = ref.read(tbApiClientProvider);
    final gen = client.sessionGeneration;

    final result = await ref
        .read(auditLogRepositoryProvider)
        .getAuditLogs(
          PageQuery(page: page, pageSize: 20),
          filter,
          cancelToken: cancelToken,
        );

    if (seq != _requestSeq || gen != client.sessionGeneration) {
      throw const TbFailure(
        type: TbFailureType.cancelled,
        message: 'Stale audit log response discarded',
      );
    }

    return PagedListState<TbAuditLog>(
      items: page == 0 ? result.data : [...existing, ...result.data],
      page: page,
      hasNext: result.hasNext,
      totalElements: result.totalElements,
    );
  }
}

final auditLogsListProvider = AsyncNotifierProvider.autoDispose
    .family<AuditLogsNotifier, PagedListState<TbAuditLog>, TbAuditLogQuery>(
      AuditLogsNotifier.new,
    );
