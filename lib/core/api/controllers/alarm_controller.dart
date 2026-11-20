import 'package:dio/dio.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:thingsboard_democloud_app/core/api/controllers/server_config_controller.dart';
import 'package:thingsboard_democloud_app/core/api/repositories/alarm_repository.dart';
import 'package:thingsboard_democloud_app/core/mock/mock_data.dart';
import 'package:thingsboard_democloud_app/core/models/alarm_models.dart';
import 'package:thingsboard_democloud_app/core/models/auth_models.dart';
import 'package:thingsboard_democloud_app/core/models/entity_id.dart';
import 'package:thingsboard_democloud_app/core/models/pagination.dart';
import 'package:thingsboard_democloud_app/core/models/tb_failure.dart';

final alarmRepositoryProvider = Provider<AlarmRepository>((ref) {
  final sessionScope = ref.watch(
    serverConfigProvider.select((s) => (s.mode, s.sessionGeneration)),
  );
  if (sessionScope.$1 == SessionMode.demo) {
    return DemoAlarmRepository(ref.read(alarmsProvider));
  }
  return RestAlarmRepository(client: ref.watch(tbApiClientProvider));
});

/// Active filter state for the main Alarms view.
final alarmFilterProvider = StateProvider.autoDispose<TbAlarmFilter>(
  (ref) => const TbAlarmFilter(),
);

/// Paginated alarms list controller with optimistic ack/clear/assign + rollback.
class AlarmsNotifier
    extends
        AutoDisposeFamilyAsyncNotifier<PagedListState<TbAlarmInfo>, EntityId?> {
  int _requestSeq = 0;
  CancelToken? _activeCancelToken;

  @override
  Future<PagedListState<TbAlarmInfo>> build(EntityId? arg) async {
    ref.onDispose(() => _activeCancelToken?.cancel('Disposed'));
    final filter = arg != null
        ? TbAlarmFilter(originatorId: arg)
        : ref.watch(alarmFilterProvider);
    return _fetchPage(page: 0, filter: filter, existing: const []);
  }

  Future<void> refresh() async {
    final filter = arg != null
        ? TbAlarmFilter(originatorId: arg)
        : ref.read(alarmFilterProvider);
    state = const AsyncLoading<PagedListState<TbAlarmInfo>>();
    state = await AsyncValue.guard(
      () => _fetchPage(page: 0, filter: filter, existing: const []),
    );
  }

  Future<void> loadNextPage() async {
    final current = state.valueOrNull;
    if (current == null || !current.hasNext || current.isLoadingMore) return;

    final filter = arg != null
        ? TbAlarmFilter(originatorId: arg)
        : ref.read(alarmFilterProvider);

    state = AsyncData(
      current.copyWith(isLoadingMore: true, clearLoadMoreError: true),
    );
    try {
      final nextState = await _fetchPage(
        page: current.page + 1,
        filter: filter,
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

  Future<void> acknowledge(String alarmId) => _mutateAlarm(
    alarmId,
    optimisticTransform: (a) => a.copyWith(acknowledged: true),
    remoteCall: () => ref.read(alarmRepositoryProvider).ackAlarm(alarmId),
  );

  Future<void> clear(String alarmId) => _mutateAlarm(
    alarmId,
    optimisticTransform: (a) => a.copyWith(cleared: true),
    remoteCall: () => ref.read(alarmRepositoryProvider).clearAlarm(alarmId),
  );

  Future<void> assign(String alarmId, TbUserEmailInfo? assignee) =>
      _mutateAlarm(
        alarmId,
        optimisticTransform: (a) => assignee == null
            ? a.copyWith(clearAssignee: true)
            : a.copyWith(
                assigneeId: assignee.id,
                assigneeName: assignee.displayName,
                assigneeEmail: assignee.email,
              ),
        remoteCall: () => assignee == null
            ? ref.read(alarmRepositoryProvider).unassignAlarm(alarmId)
            : ref
                  .read(alarmRepositoryProvider)
                  .assignAlarm(alarmId, assignee.id),
      );

  Future<void> _mutateAlarm(
    String alarmId, {
    required TbAlarmInfo Function(TbAlarmInfo) optimisticTransform,
    required Future<TbAlarmInfo> Function() remoteCall,
  }) async {
    final previous = state.valueOrNull;
    if (previous != null) {
      final updated = [
        for (final item in previous.items)
          if (item.id == alarmId) optimisticTransform(item) else item,
      ];
      state = AsyncData(previous.copyWith(items: updated));
    }

    try {
      final confirmed = await remoteCall();
      final latest = state.valueOrNull;
      if (latest != null) {
        state = AsyncData(
          latest.copyWith(
            items: [
              for (final item in latest.items)
                if (item.id == alarmId) confirmed else item,
            ],
          ),
        );
      }
      ref.invalidate(alarmDetailsProvider(alarmId));
    } catch (_) {
      if (previous != null) {
        state = AsyncData(previous);
      }
      rethrow;
    }
  }

  Future<PagedListState<TbAlarmInfo>> _fetchPage({
    required int page,
    required TbAlarmFilter filter,
    required List<TbAlarmInfo> existing,
  }) async {
    final seq = ++_requestSeq;
    _activeCancelToken?.cancel('Superseded by newer alarm query');
    final cancelToken = CancelToken();
    _activeCancelToken = cancelToken;

    final client = ref.read(tbApiClientProvider);
    final gen = client.sessionGeneration;

    final result = await ref
        .read(alarmRepositoryProvider)
        .getAlarms(
          PageQuery(page: page, pageSize: 20),
          filter,
          cancelToken: cancelToken,
        );

    if (seq != _requestSeq || gen != client.sessionGeneration) {
      throw const TbFailure(
        type: TbFailureType.cancelled,
        message: 'Stale alarm response discarded',
      );
    }

    return PagedListState<TbAlarmInfo>(
      items: page == 0 ? result.data : [...existing, ...result.data],
      page: page,
      hasNext: result.hasNext,
      totalElements: result.totalElements,
    );
  }
}

final alarmsListProvider = AsyncNotifierProvider.autoDispose
    .family<AlarmsNotifier, PagedListState<TbAlarmInfo>, EntityId?>(
      AlarmsNotifier.new,
    );

/// Detail state for a single alarm supporting optimistic ack/clear/assign.
class AlarmDetailsNotifier
    extends AutoDisposeFamilyAsyncNotifier<TbAlarmInfo, String> {
  @override
  Future<TbAlarmInfo> build(String arg) {
    return ref.watch(alarmRepositoryProvider).getAlarmInfo(arg);
  }

  Future<void> acknowledge() => _mutate(
    (a) => a.copyWith(acknowledged: true),
    () => ref.read(alarmRepositoryProvider).ackAlarm(arg),
  );

  Future<void> clear() => _mutate(
    (a) => a.copyWith(cleared: true),
    () => ref.read(alarmRepositoryProvider).clearAlarm(arg),
  );

  Future<void> assign(TbUserEmailInfo? assignee) => _mutate(
    (a) => assignee == null
        ? a.copyWith(clearAssignee: true)
        : a.copyWith(
            assigneeId: assignee.id,
            assigneeName: assignee.displayName,
            assigneeEmail: assignee.email,
          ),
    () => assignee == null
        ? ref.read(alarmRepositoryProvider).unassignAlarm(arg)
        : ref.read(alarmRepositoryProvider).assignAlarm(arg, assignee.id),
  );

  Future<void> _mutate(
    TbAlarmInfo Function(TbAlarmInfo) optimistic,
    Future<TbAlarmInfo> Function() remote,
  ) async {
    final prev = state.valueOrNull;
    if (prev != null) {
      state = AsyncData(optimistic(prev));
    }
    try {
      final confirmed = await remote();
      state = AsyncData(confirmed);
      ref.invalidate(alarmCommentsProvider(arg));
    } catch (_) {
      if (prev != null) state = AsyncData(prev);
      rethrow;
    }
  }
}

final alarmDetailsProvider = AsyncNotifierProvider.autoDispose
    .family<AlarmDetailsNotifier, TbAlarmInfo, String>(
      AlarmDetailsNotifier.new,
    );

/// Alarm comments controller supporting pagination and comment creation.
class AlarmCommentsNotifier
    extends
        AutoDisposeFamilyAsyncNotifier<PagedListState<TbAlarmComment>, String> {
  @override
  Future<PagedListState<TbAlarmComment>> build(String arg) async {
    final page = await ref
        .watch(alarmRepositoryProvider)
        .getComments(arg, const PageQuery(pageSize: 50));
    return PagedListState<TbAlarmComment>(
      items: page.data,
      hasNext: page.hasNext,
      totalElements: page.totalElements,
    );
  }

  Future<void> addComment(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    final created = await ref
        .read(alarmRepositoryProvider)
        .addComment(arg, trimmed);
    final current = state.valueOrNull;
    if (current != null) {
      state = AsyncData(
        current.copyWith(
          items: [...current.items, created],
          totalElements: current.totalElements + 1,
        ),
      );
    }
  }
}

final alarmCommentsProvider = AsyncNotifierProvider.autoDispose
    .family<AlarmCommentsNotifier, PagedListState<TbAlarmComment>, String>(
      AlarmCommentsNotifier.new,
    );

final alarmAssigneesProvider = FutureProvider.autoDispose
    .family<List<TbUserEmailInfo>, ({String alarmId, String search})>((
      ref,
      params,
    ) async {
      final page = await ref
          .watch(alarmRepositoryProvider)
          .getAssignees(
            params.alarmId,
            PageQuery(pageSize: 30, textSearch: params.search),
          );
      return page.data;
    });
