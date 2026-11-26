import 'package:dio/dio.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:thingsboard_democloud_app/core/api/controllers/auth_controller.dart';
import 'package:thingsboard_democloud_app/core/api/controllers/device_controller.dart';
import 'package:thingsboard_democloud_app/core/api/controllers/server_config_controller.dart';
import 'package:thingsboard_democloud_app/core/api/controllers/telemetry_controller.dart';
import 'package:thingsboard_democloud_app/core/api/repositories/dashboard_repository.dart';
import 'package:thingsboard_democloud_app/core/mock/mock_data.dart';
import 'package:thingsboard_democloud_app/core/models/auth_models.dart';
import 'package:thingsboard_democloud_app/core/models/dashboard_models.dart';
import 'package:thingsboard_democloud_app/core/models/device_models.dart';
import 'package:thingsboard_democloud_app/core/models/entity_id.dart';
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

    final repo = ref.read(dashboardRepositoryProvider);
    final result = await repo.getDashboards(
      PageQuery(page: page, pageSize: 20, textSearch: textSearch),
      authority: session?.authority,
      customerId: session?.customerId,
      cancelToken: cancelToken,
    );

    Set<String> starredIds = const <String>{};
    try {
      final userDashboards = await repo.getLastVisitedDashboards();
      starredIds = userDashboards.starred.map((e) => e.id).toSet();
    } catch (_) {
      // Optional PE 4.4 capability; ignore errors.
    }

    if (seq != _requestSeq || gen != client.sessionGeneration) {
      throw const TbFailure(
        type: TbFailureType.cancelled,
        message: 'Stale dashboard response discarded',
      );
    }

    final mergedData = starredIds.isEmpty
        ? result.data
        : result.data
              .map(
                (d) => starredIds.contains(d.id) && !d.isStarred
                    ? d.copyWith(isStarred: true)
                    : d,
              )
              .toList(growable: false);

    return PagedListState<TbDashboardInfo>(
      items: page == 0 ? mergedData : [...existing, ...mergedData],
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

typedef _TelemetryTarget = ({EntityId id, String? name});

/// Resolves the concrete telemetry [EntityId] for a dashboard, supporting
/// widget-referenced aliases, 404 skipping for deleted devices, active-telemetry
/// probing across multi-device dashboards, and dynamic `deviceType` aliases.
/// [name] is only set when a device list was already loaded (no extra request).
final _dashboardTelemetryTargetProvider = FutureProvider.autoDispose
    .family<_TelemetryTarget, String>((ref, dashboardId) async {
      final dashboard = await ref.watch(
        dashboardDetailsProvider(dashboardId).future,
      );
      final mode = ref.watch(serverConfigProvider.select((s) => s.mode));
      final candidates = dashboard.resolveCandidateTelemetryEntities();

      if (mode != SessionMode.live) {
        return (
          id:
              candidates.firstOrNull ??
              EntityId(entityType: EntityType.dashboard, id: dashboard.info.id),
          name: null,
        );
      }

      EntityId? firstExistingCandidate;
      if (candidates.isNotEmpty) {
        final telemetryRepo = ref.watch(telemetryRepositoryProvider);
        for (final candidate in candidates) {
          try {
            final latest = await telemetryRepo.getLatestTimeseries(candidate);
            firstExistingCandidate ??= candidate;
            if (latest.isNotEmpty) {
              return (id: candidate, name: null);
            }
          } on TbFailure catch (e) {
            if (e.type == TbFailureType.notFound) {
              continue;
            }
            firstExistingCandidate ??= candidate;
          } catch (_) {
            firstExistingCandidate ??= candidate;
          }
        }
      }

      final aliasFilter = dashboard.extractDynamicDeviceAliasFilter();
      if (aliasFilter != null) {
        try {
          final page = await ref
              .watch(deviceRepositoryProvider)
              .getDevices(
                const PageQuery(page: 0, pageSize: 10),
                TbDeviceQuery(
                  deviceType: aliasFilter.deviceType,
                  textSearch: aliasFilter.nameSearch,
                ),
              );
          if (page.data.isNotEmpty) {
            final chosen =
                page.data.where((d) => d.active).firstOrNull ?? page.data.first;
            return (
              id: EntityId(entityType: EntityType.device, id: chosen.id),
              name: chosen.name,
            );
          }
        } catch (_) {
          // Fall through if dynamic device lookup fails.
        }
      }

      if (firstExistingCandidate != null) {
        return (id: firstExistingCandidate, name: null);
      }

      if (candidates.any((c) => c.entityType == EntityType.device)) {
        try {
          final page = await ref
              .watch(deviceRepositoryProvider)
              .getDevices(
                const PageQuery(page: 0, pageSize: 10),
                const TbDeviceQuery(),
              );
          if (page.data.isNotEmpty) {
            final chosen =
                page.data.where((d) => d.active).firstOrNull ?? page.data.first;
            return (
              id: EntityId(entityType: EntityType.device, id: chosen.id),
              name: chosen.name,
            );
          }
        } catch (_) {
          // Fall through to dashboard entity ID.
        }
      }

      return (
        id: EntityId(entityType: EntityType.dashboard, id: dashboard.info.id),
        name: null,
      );
    });

final dashboardTelemetryEntityProvider = FutureProvider.autoDispose
    .family<EntityId, String>((ref, dashboardId) async {
      return (await ref.watch(
        _dashboardTelemetryTargetProvider(dashboardId).future,
      )).id;
    });

/// Display name of the resolved telemetry target, or null when unknown.
final dashboardTargetNameProvider = Provider.autoDispose
    .family<String?, String>((ref, dashboardId) {
      return ref
          .watch(_dashboardTelemetryTargetProvider(dashboardId))
          .valueOrNull
          ?.name;
    });
