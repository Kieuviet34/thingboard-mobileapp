import 'dart:async';

import 'package:dio/dio.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:thingsboard_democloud_app/core/api/controllers/server_config_controller.dart';
import 'package:thingsboard_democloud_app/core/api/repositories/telemetry_repository.dart';
import 'package:thingsboard_democloud_app/core/api/ws/telemetry_ws_service.dart';
import 'package:thingsboard_democloud_app/core/mock/mock_data.dart';
import 'package:thingsboard_democloud_app/core/models/auth_models.dart';
import 'package:thingsboard_democloud_app/core/models/entity_id.dart';
import 'package:thingsboard_democloud_app/core/models/tb_failure.dart';
import 'package:thingsboard_democloud_app/core/models/telemetry_models.dart';

final telemetryRepositoryProvider = Provider<TelemetryRepository>((ref) {
  final sessionScope = ref.watch(
    serverConfigProvider.select((s) => (s.mode, s.sessionGeneration)),
  );
  if (sessionScope.$1 == SessionMode.demo) {
    return DemoTelemetryRepository(ref.read(devicesProvider));
  }
  return RestTelemetryRepository(client: ref.watch(tbApiClientProvider));
});

/// Entity attributes controller supporting read/save/delete by scope.
class EntityAttributesNotifier
    extends
        AutoDisposeFamilyAsyncNotifier<
          List<TbAttributeEntry>,
          ({EntityId id, TbAttributeScope scope})
        > {
  @override
  Future<List<TbAttributeEntry>> build(
    ({EntityId id, TbAttributeScope scope}) arg,
  ) {
    return ref
        .watch(telemetryRepositoryProvider)
        .getAttributes(arg.id, arg.scope);
  }

  Future<void> saveAttributes(Map<String, dynamic> attributes) async {
    await ref
        .read(telemetryRepositoryProvider)
        .saveAttributes(arg.id, arg.scope, attributes);
    ref.invalidateSelf();
  }

  Future<void> deleteAttributes(List<String> keys) async {
    await ref
        .read(telemetryRepositoryProvider)
        .deleteAttributes(arg.id, arg.scope, keys);
    ref.invalidateSelf();
  }
}

final entityAttributesProvider = AsyncNotifierProvider.autoDispose
    .family<
      EntityAttributesNotifier,
      List<TbAttributeEntry>,
      ({EntityId id, TbAttributeScope scope})
    >(EntityAttributesNotifier.new);

final entityLatestTelemetryProvider = FutureProvider.autoDispose
    .family<Map<String, TbTsPoint>, EntityId>((ref, entityId) {
      return ref
          .watch(telemetryRepositoryProvider)
          .getLatestTimeseries(entityId);
    });

/// Historical telemetry controller with `_requestSeq` + `CancelToken` race guard
/// so overlapping range/aggregation requests never overwrite newer chart data.
class TelemetryHistoryNotifier
    extends
        AutoDisposeFamilyAsyncNotifier<Map<String, List<TbTsPoint>>, EntityId> {
  int _requestSeq = 0;
  CancelToken? _activeCancelToken;

  @override
  Future<Map<String, List<TbTsPoint>>> build(EntityId arg) async {
    ref.onDispose(() => _activeCancelToken?.cancel('Disposed'));
    final now = DateTime.now().millisecondsSinceEpoch;
    final startTs = now - const Duration(hours: 24).inMilliseconds;
    return _fetch(
      TbTsHistoryQuery(
        entityId: arg,
        keys: const [],
        startTs: startTs,
        endTs: now,
      ),
    );
  }

  Future<void> loadRange(TbTsHistoryQuery query) async {
    state = const AsyncLoading<Map<String, List<TbTsPoint>>>();
    state = await AsyncValue.guard(() => _fetch(query));
  }

  Future<Map<String, List<TbTsPoint>>> _fetch(TbTsHistoryQuery query) async {
    final seq = ++_requestSeq;
    _activeCancelToken?.cancel('Superseded by newer telemetry history query');
    final cancelToken = CancelToken();
    _activeCancelToken = cancelToken;

    final client = ref.read(tbApiClientProvider);
    final gen = client.sessionGeneration;

    final data = await ref
        .read(telemetryRepositoryProvider)
        .getTimeseriesHistory(query, cancelToken: cancelToken);

    if (seq != _requestSeq || gen != client.sessionGeneration) {
      throw const TbFailure(
        type: TbFailureType.cancelled,
        message: 'Stale telemetry history response discarded',
      );
    }
    return data;
  }
}

final entityTelemetryHistoryProvider = AsyncNotifierProvider.autoDispose
    .family<TelemetryHistoryNotifier, Map<String, List<TbTsPoint>>, EntityId>(
      TelemetryHistoryNotifier.new,
    );

/// Live entity telemetry stream (WS `ENTITY_DATA` in Live mode, initial snapshot in Demo mode).
final liveEntityTelemetryProvider = StreamProvider.autoDispose
    .family<Map<String, TbTsPoint>, ({EntityId id, List<String> keys})>((
      ref,
      params,
    ) {
      final mode = ref.watch(serverConfigProvider.select((s) => s.mode));
      if (mode == SessionMode.demo) {
        return Stream.fromFuture(
          ref
              .read(telemetryRepositoryProvider)
              .getLatestTimeseries(params.id, keys: params.keys),
        );
      }

      final ws = ref.watch(telemetryWsServiceProvider);
      final stream = ws.subscribe(
        type: WsCommandType.entityData,
        payload: <String, dynamic>{
          'query': <String, dynamic>{
            'entityFilter': <String, dynamic>{
              'type': 'singleEntity',
              'singleEntity': params.id.toJson(),
            },
            'pageLink': const <String, dynamic>{'pageSize': 1, 'page': 0},
            'latestValues': [
              for (final k in params.keys)
                <String, dynamic>{'type': 'TIME_SERIES', 'key': k},
            ],
          },
          'latestCmd': <String, dynamic>{
            'keys': [
              for (final k in params.keys)
                <String, dynamic>{'type': 'TIME_SERIES', 'key': k},
            ],
          },
        },
      );

      // Not an `async*` generator on purpose: when the provider is disposed
      // while parked on the socket stream, a generator only notices at its
      // next `yield`, so the WS subscription (and its *_UNSUBSCRIBE frame)
      // would leak. Cancel the socket subscription explicitly instead.
      final output = StreamController<Map<String, TbTsPoint>>();
      var merged = <String, Map<String, TbTsPoint>>{};
      final subscription = stream.listen(
        (frame) {
          // A malformed server frame must surface as a stream error (so the
          // UI shows its error state), not escape as an uncaught zone error.
          try {
            merged = mergeEntityDataUpdates(current: merged, frame: frame);
            output.add(merged[params.id.id] ?? const <String, TbTsPoint>{});
          } catch (error, stackTrace) {
            output.addError(error, stackTrace);
          }
        },
        onError: output.addError,
        onDone: output.close,
      );
      ref.onDispose(() {
        unawaited(subscription.cancel());
        unawaited(output.close());
      });
      return output.stream;
    });
