import 'package:dio/dio.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:thingsboard_democloud_app/core/api/controllers/server_config_controller.dart';
import 'package:thingsboard_democloud_app/core/api/repositories/notification_repository.dart';
import 'package:thingsboard_democloud_app/core/api/ws/telemetry_ws_service.dart';
import 'package:thingsboard_democloud_app/core/mock/mock_data.dart';
import 'package:thingsboard_democloud_app/core/models/auth_models.dart';
import 'package:thingsboard_democloud_app/core/models/notification_models.dart';
import 'package:thingsboard_democloud_app/core/models/pagination.dart';
import 'package:thingsboard_democloud_app/core/models/tb_failure.dart';

final notificationRepositoryProvider = Provider<NotificationRepository>((ref) {
  final sessionScope = ref.watch(
    serverConfigProvider.select((s) => (s.mode, s.sessionGeneration)),
  );
  if (sessionScope.$1 == SessionMode.demo) {
    return DemoNotificationRepository(ref.read(notificationsProvider));
  }
  return RestNotificationRepository(client: ref.watch(tbApiClientProvider));
});

/// Paginated notifications controller with mark-read, mark-all-read, delete, and race guard.
class NotificationsListNotifier
    extends
        AutoDisposeFamilyAsyncNotifier<PagedListState<TbNotification>, bool> {
  int _requestSeq = 0;
  CancelToken? _activeCancelToken;

  @override
  Future<PagedListState<TbNotification>> build(bool arg) async {
    ref.onDispose(() => _activeCancelToken?.cancel('Disposed'));
    return _fetchPage(page: 0, unreadOnly: arg, existing: const []);
  }

  Future<void> refresh() async {
    state = const AsyncLoading<PagedListState<TbNotification>>();
    state = await AsyncValue.guard(
      () => _fetchPage(page: 0, unreadOnly: arg, existing: const []),
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
        unreadOnly: arg,
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

  Future<void> markAsRead(String notificationId) async {
    await ref.read(notificationRepositoryProvider).markAsRead(notificationId);
    final current = state.valueOrNull;
    if (current != null) {
      final updated = [
        for (final n in current.items)
          if (n.id == notificationId) n.copyWith(isRead: true) else n,
      ];
      state = AsyncData(
        current.copyWith(
          items: arg ? updated.where((n) => !n.isRead).toList() : updated,
        ),
      );
    }
    ref.invalidate(notificationsListProvider(!arg));
    ref.invalidate(unreadNotificationsCountProvider);
  }

  Future<void> markAllAsRead() async {
    await ref.read(notificationRepositoryProvider).markAllAsRead();
    final current = state.valueOrNull;
    if (current != null) {
      final updated = arg
          ? const <TbNotification>[]
          : [for (final n in current.items) n.copyWith(isRead: true)];
      state = AsyncData(current.copyWith(items: updated));
    }
    ref.invalidate(notificationsListProvider(!arg));
    ref.invalidate(unreadNotificationsCountProvider);
  }

  Future<void> deleteNotification(String notificationId) async {
    await ref
        .read(notificationRepositoryProvider)
        .deleteNotification(notificationId);
    final current = state.valueOrNull;
    if (current != null) {
      state = AsyncData(
        current.copyWith(
          items: current.items.where((n) => n.id != notificationId).toList(),
          totalElements: (current.totalElements - 1).clamp(0, 1 << 30),
        ),
      );
    }
    ref.invalidate(notificationsListProvider(!arg));
    ref.invalidate(unreadNotificationsCountProvider);
  }

  Future<PagedListState<TbNotification>> _fetchPage({
    required int page,
    required bool unreadOnly,
    required List<TbNotification> existing,
  }) async {
    final seq = ++_requestSeq;
    _activeCancelToken?.cancel('Superseded by newer notifications query');
    final cancelToken = CancelToken();
    _activeCancelToken = cancelToken;

    final client = ref.read(tbApiClientProvider);
    final gen = client.sessionGeneration;

    final result = await ref
        .read(notificationRepositoryProvider)
        .getNotifications(
          PageQuery(page: page, pageSize: 20),
          unreadOnly: unreadOnly,
          cancelToken: cancelToken,
        );

    if (seq != _requestSeq || gen != client.sessionGeneration) {
      throw const TbFailure(
        type: TbFailureType.cancelled,
        message: 'Stale notifications response discarded',
      );
    }

    return PagedListState<TbNotification>(
      items: page == 0 ? result.data : [...existing, ...result.data],
      page: page,
      hasNext: result.hasNext,
      totalElements: result.totalElements,
    );
  }
}

final notificationsListProvider = AsyncNotifierProvider.autoDispose
    .family<NotificationsListNotifier, PagedListState<TbNotification>, bool>(
      NotificationsListNotifier.new,
    );

/// Live unread notification count stream (WS `NOTIFICATIONS_COUNT` in Live mode,
/// direct repository query in Demo mode invalidated on notification mutations).
final unreadNotificationsCountProvider = StreamProvider.autoDispose<int>((ref) {
  final mode = ref.watch(serverConfigProvider.select((s) => s.mode));
  final repo = ref.watch(notificationRepositoryProvider);

  if (mode == SessionMode.demo) {
    return Stream<int>.fromFuture(repo.getUnreadCount());
  }

  final ws = ref.watch(telemetryWsServiceProvider);
  return _liveUnreadCountStream(repo: repo, ws: ws);
});

Stream<int> _liveUnreadCountStream({
  required NotificationRepository repo,
  required TbWebSocketService ws,
}) async* {
  final initialCount = await repo.getUnreadCount();
  yield initialCount;

  final stream = ws.subscribe(type: WsCommandType.notificationsCount);
  await for (final frame in stream) {
    final count = (frame['totalUnreadCount'] as num?)?.toInt();
    if (count != null) {
      yield count;
    }
  }
}

class NotificationSettingsNotifier
    extends AutoDisposeAsyncNotifier<TbUserNotificationSettings> {
  @override
  Future<TbUserNotificationSettings> build() {
    return ref.watch(notificationRepositoryProvider).getNotificationSettings();
  }

  Future<void> save(TbUserNotificationSettings settings) async {
    final saved = await ref
        .read(notificationRepositoryProvider)
        .saveNotificationSettings(settings);
    state = AsyncData(saved);
  }
}

final notificationSettingsProvider =
    AsyncNotifierProvider.autoDispose<
      NotificationSettingsNotifier,
      TbUserNotificationSettings
    >(NotificationSettingsNotifier.new);
