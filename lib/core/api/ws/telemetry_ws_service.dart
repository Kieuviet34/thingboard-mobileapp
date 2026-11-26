import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:thingsboard_democloud_app/core/api/client/tb_error_mapper.dart';
import 'package:thingsboard_democloud_app/core/models/tb_failure.dart';
import 'package:thingsboard_democloud_app/core/models/telemetry_models.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// Connection lifecycle states for [TbWebSocketService].
enum WsConnectionState { disconnected, connecting, authenticated, reconnecting }

/// Supported ThingsBoard WebSocket subscription commands and unsubscribe contracts.
enum WsCommandType {
  entityData('ENTITY_DATA', unsubscribeWire: 'ENTITY_DATA_UNSUBSCRIBE'),
  entityCount('ENTITY_COUNT', unsubscribeWire: 'ENTITY_COUNT_UNSUBSCRIBE'),
  alarmData('ALARM_DATA', unsubscribeWire: 'ALARM_DATA_UNSUBSCRIBE'),
  alarmCount('ALARM_COUNT', unsubscribeWire: 'ALARM_COUNT_UNSUBSCRIBE'),
  alarmStatus('ALARM_STATUS', unsubscribeWire: 'ALARM_STATUS_UNSUBSCRIBE'),
  notifications('NOTIFICATIONS', unsubscribeWire: 'NOTIFICATIONS_UNSUBSCRIBE'),

  /// Server does not accept an unsubscribe frame for `NOTIFICATIONS_COUNT`.
  notificationsCount('NOTIFICATIONS_COUNT'),
  attributes('ATTRIBUTES', isLegacyV1: true),
  timeseries('TIMESERIES', isLegacyV1: true),
  timeseriesHistory('TIMESERIES_HISTORY');

  const WsCommandType(
    this.wireValue, {
    this.unsubscribeWire,
    this.isLegacyV1 = false,
  });

  final String wireValue;
  final String? unsubscribeWire;
  final bool isLegacyV1;
}

class _ActiveSubscription {
  _ActiveSubscription({
    required this.cmdId,
    required this.type,
    required this.payload,
    required this.controller,
  });

  final int cmdId;
  final WsCommandType type;
  final Map<String, dynamic> payload;
  final StreamController<Map<String, dynamic>> controller;
}

/// Shared WebSocket multiplexer for `wss://<host>/api/ws` (PE 4.4.x / 3.4+),
/// with automatic handshake fallback to `wss://<host>/api/ws/plugins/telemetry?token=<jwt>`
/// (`TelemetryPluginCmdsWrapper`) for ThingsBoard 3.3.x servers.
///
/// Features:
/// - Single connection with `authCmd` on `/api/ws` (or query token on 3.3 fallback)
/// - 30-second application heartbeat (< 90s server idle timeout)
/// - `socketGeneration` scoping so stale frames never cross reconnects
/// - Immediate local intent cleanup on offline dispose
/// - Per-command unsubscribe (no unsupported unsubscribe for `NOTIFICATIONS_COUNT`)
class TbWebSocketService {
  TbWebSocketService({
    required Uri Function() wsUriProvider,
    required Future<String?> Function() tokenProvider,
    WebSocketChannel Function(Uri uri)? channelFactory,
    this.heartbeatInterval = const Duration(seconds: 30),
    this.baseReconnectDelay = const Duration(milliseconds: 500),
    this.onAuthFailure,
  }) : _wsUriProvider = wsUriProvider,
       _tokenProvider = tokenProvider,
       _channelFactory = channelFactory ?? WebSocketChannel.connect;

  final Uri Function() _wsUriProvider;
  final Future<String?> Function() _tokenProvider;
  final WebSocketChannel Function(Uri uri) _channelFactory;
  final Duration heartbeatInterval;
  final Duration baseReconnectDelay;
  final void Function(TbFailure failure)? onAuthFailure;

  final _stateController = StreamController<WsConnectionState>.broadcast();
  final Map<int, _ActiveSubscription> _activeSubscriptions = {};

  WsConnectionState _currentState = WsConnectionState.disconnected;
  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _socketSub;
  Timer? _heartbeatTimer;
  Timer? _reconnectTimer;

  int _socketGeneration = 0;
  int _nextCmdId = 1;
  int _reconnectAttempt = 0;
  bool _disposed = false;
  bool _manuallyPausedOrClosed = false;
  bool _useLegacyTelemetryEndpoint = false;

  WsConnectionState get currentState => _currentState;
  Stream<WsConnectionState> get connectionStateStream =>
      _stateController.stream;
  int get socketGeneration => _socketGeneration;

  /// Builds the `ws://` or `wss://` ThingsBoard `/api/ws` URI from a base HTTP URL.
  static Uri buildWsUri(String baseUrl) {
    final parsed = Uri.parse(baseUrl.trim());
    final scheme = parsed.scheme == 'https' ? 'wss' : 'ws';
    return parsed.replace(
      scheme: scheme,
      path: '/api/ws',
      query: null,
      fragment: null,
    );
  }

  /// Builds the legacy ThingsBoard 3.3.x `/api/ws/plugins/telemetry?token=...` URI
  /// from the primary `/api/ws` URI without logging or persisting the token.
  static Uri _buildLegacyTelemetryUri(Uri primaryWsUri, String token) {
    return primaryWsUri.replace(
      path: '/api/ws/plugins/telemetry',
      queryParameters: <String, String>{'token': token},
      fragment: null,
    );
  }

  /// Opens the WebSocket connection and sends `authCmd` + any active subscriptions.
  Future<void> connect() async {
    if (_disposed) return;
    if (_currentState == WsConnectionState.authenticated ||
        _currentState == WsConnectionState.connecting) {
      return;
    }
    _manuallyPausedOrClosed = false;
    await _openSocket(isReconnect: false);
  }

  /// Subscribes to a ThingsBoard WebSocket command and yields matching JSON frames.
  ///
  /// Cancelling the returned stream automatically removes local intent and sends
  /// the command-appropriate unsubscribe frame if connected.
  Stream<Map<String, dynamic>> subscribe({
    required WsCommandType type,
    Map<String, dynamic> payload = const {},
  }) {
    final cmdId = _nextCmdId++;
    late final StreamController<Map<String, dynamic>> controller;
    controller = StreamController<Map<String, dynamic>>(
      onCancel: () => _unsubscribe(cmdId),
    );

    final sub = _ActiveSubscription(
      cmdId: cmdId,
      type: type,
      payload: Map<String, dynamic>.from(payload),
      controller: controller,
    );
    _activeSubscriptions[cmdId] = sub;

    if (_currentState == WsConnectionState.authenticated) {
      final frame = _buildSubscribeFrame(sub);
      if (frame != null) {
        _sendJson(frame);
      }
    } else if (!_manuallyPausedOrClosed &&
        _currentState == WsConnectionState.disconnected) {
      unawaited(connect());
    }

    return controller.stream;
  }

  /// Closes the socket cleanly without destroying active subscription intent
  /// if [preserveSubscriptions] is true (used for lifecycle pause).
  Future<void> disconnect({bool preserveSubscriptions = false}) async {
    _manuallyPausedOrClosed = true;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    if (!preserveSubscriptions) {
      final controllers = _activeSubscriptions.values
          .map((e) => e.controller)
          .toList(growable: false);
      _activeSubscriptions.clear();
      for (final c in controllers) {
        if (!c.isClosed) await c.close();
      }
    }
    await _closeSocketOnly();
    _setState(WsConnectionState.disconnected);
  }

  /// Resets the WebSocket session on logout, host switch, or `SessionMode` change.
  Future<void> resetSession() async {
    _useLegacyTelemetryEndpoint = false;
    await disconnect(preserveSubscriptions: false);
  }

  /// Pauses socket on background and reconnects with fresh JWT on resume.
  Future<void> handleAppLifecycleState(AppLifecycleState state) async {
    if (_disposed) return;
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      await disconnect(preserveSubscriptions: true);
    } else if (state == AppLifecycleState.resumed &&
        _activeSubscriptions.isNotEmpty) {
      _manuallyPausedOrClosed = false;
      await _openSocket(isReconnect: true);
    }
  }

  /// Re-opens the live socket so `authCmd` carries the current stored JWT
  /// (e.g. after `/api/auth/changePassword` rotated the pair). Subscriptions
  /// are replayed; an idle/closed service picks up the new token on next connect.
  Future<void> reauthenticate() async {
    if (_disposed ||
        _manuallyPausedOrClosed ||
        _currentState == WsConnectionState.disconnected) {
      return;
    }
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    await _openSocket(isReconnect: true);
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await disconnect(preserveSubscriptions: false);
    if (!_stateController.isClosed) {
      await _stateController.close();
    }
  }

  Future<void> _openSocket({required bool isReconnect}) async {
    if (_disposed || _manuallyPausedOrClosed) return;
    await _closeSocketOnly();

    final gen = ++_socketGeneration;
    _setState(
      isReconnect
          ? WsConnectionState.reconnecting
          : WsConnectionState.connecting,
    );

    try {
      final token = await _tokenProvider();
      if (_disposed || _manuallyPausedOrClosed || gen != _socketGeneration) {
        return;
      }
      if (token == null || token.isEmpty) {
        _setState(WsConnectionState.disconnected);
        return;
      }

      final primaryUri = _wsUriProvider();
      WebSocketChannel channel;
      if (_useLegacyTelemetryEndpoint) {
        channel = _channelFactory(_buildLegacyTelemetryUri(primaryUri, token));
        _channel = channel;
        await channel.ready;
      } else {
        channel = _channelFactory(primaryUri);
        _channel = channel;
        try {
          await channel.ready;
        } catch (_) {
          await channel.sink.close();
          if (_disposed ||
              _manuallyPausedOrClosed ||
              gen != _socketGeneration) {
            return;
          }
          // Pre-3.4 ThingsBoard rejects unauthenticated `/api/ws` upgrades with 401
          // and exposes `/api/ws/plugins/telemetry?token=<jwt>` instead.
          final legacyChannel = _channelFactory(
            _buildLegacyTelemetryUri(primaryUri, token),
          );
          _channel = legacyChannel;
          await legacyChannel.ready;
          channel = legacyChannel;
          _useLegacyTelemetryEndpoint = true;
        }
      }

      if (_disposed || _manuallyPausedOrClosed || gen != _socketGeneration) {
        await channel.sink.close();
        return;
      }

      _socketSub = channel.stream.listen(
        (raw) => _onMessage(gen, raw),
        onError: (Object err) => _onSocketDropped(gen, err),
        onDone: () => _onSocketDropped(gen, null),
        cancelOnError: false,
      );

      // First frame on `/api/ws` (PE 4.4.x / 3.4+): authCmd.
      if (!_useLegacyTelemetryEndpoint) {
        _sendJson(<String, dynamic>{
          'authCmd': <String, dynamic>{'cmdId': 0, 'token': token},
        });
      }

      _reconnectAttempt = 0;
      _setState(WsConnectionState.authenticated);
      _startHeartbeat(gen);

      // Replay active subscriptions.
      if (_activeSubscriptions.isNotEmpty) {
        for (final sub in _activeSubscriptions.values) {
          final frame = _buildSubscribeFrame(sub);
          if (frame != null) {
            _sendJson(frame);
          }
        }
      }
    } catch (error) {
      if (gen == _socketGeneration && !_disposed && !_manuallyPausedOrClosed) {
        _scheduleReconnect(gen);
      }
    }
  }

  void _onMessage(int gen, dynamic raw) {
    if (gen != _socketGeneration || _disposed) return;
    if (raw is! String) return;

    Map<String, dynamic> decoded;
    try {
      final parsed = jsonDecode(raw);
      if (parsed is! Map<String, dynamic>) return;
      decoded = parsed;
    } catch (_) {
      return;
    }

    final cmdId = (decoded['cmdId'] as num?)?.toInt();
    if (cmdId == null || cmdId == 0) return;

    final sub = _activeSubscriptions[cmdId];
    if (sub == null || sub.controller.isClosed) return;

    final errorCode = (decoded['errorCode'] as num?)?.toInt() ?? 0;
    if (errorCode != 0) {
      final failure = TbErrorMapper.fromWsErrorCode(
        errorCode,
        decoded['errorMsg'] as String?,
      );
      sub.controller.addError(failure);
      if (errorCode == 3) {
        onAuthFailure?.call(failure);
      }
      return;
    }

    sub.controller.add(decoded);
  }

  void _onSocketDropped(int gen, Object? error) {
    if (gen != _socketGeneration || _disposed || _manuallyPausedOrClosed) {
      return;
    }
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    if (_activeSubscriptions.isEmpty) {
      _setState(WsConnectionState.disconnected);
      return;
    }
    _scheduleReconnect(gen);
  }

  void _scheduleReconnect(int gen) {
    if (gen != _socketGeneration || _disposed || _manuallyPausedOrClosed) {
      return;
    }
    _reconnectTimer?.cancel();
    _setState(WsConnectionState.reconnecting);
    final multiplier = 1 << math.min(_reconnectAttempt, 5);
    _reconnectAttempt++;
    final delay = baseReconnectDelay * multiplier;
    _reconnectTimer = Timer(delay, () {
      if (!_disposed && !_manuallyPausedOrClosed) {
        unawaited(_openSocket(isReconnect: true));
      }
    });
  }

  void _startHeartbeat(int gen) {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(heartbeatInterval, (_) {
      if (gen != _socketGeneration ||
          _disposed ||
          _currentState != WsConnectionState.authenticated) {
        return;
      }
      // Valid empty command batch keeps the 90s server idle timeout reset.
      _sendJson(
        _useLegacyTelemetryEndpoint
            ? const <String, dynamic>{'attrSubCmds': <Object>[]}
            : const <String, dynamic>{'cmds': <Object>[]},
      );
    });
  }

  Future<void> _unsubscribe(int cmdId) async {
    final removed = _activeSubscriptions.remove(cmdId);
    if (removed == null) return;

    if (_currentState == WsConnectionState.authenticated &&
        !_manuallyPausedOrClosed) {
      final frame = _buildUnsubscribeFrame(removed);
      if (frame != null) {
        _sendJson(frame);
      }
    }

    if (!removed.controller.isClosed) {
      await removed.controller.close();
    }
  }

  Map<String, dynamic>? _buildSubscribeFrame(_ActiveSubscription sub) {
    if (!_useLegacyTelemetryEndpoint) {
      return <String, dynamic>{
        'cmds': <Map<String, dynamic>>[
          <String, dynamic>{
            ...sub.payload,
            'cmdId': sub.cmdId,
            'type': sub.type.wireValue,
          },
        ],
      };
    }

    final cmdBody = <String, dynamic>{...sub.payload, 'cmdId': sub.cmdId};
    return switch (sub.type) {
      WsCommandType.entityData => <String, dynamic>{
        'entityDataCmds': <Map<String, dynamic>>[cmdBody],
      },
      WsCommandType.entityCount => <String, dynamic>{
        'entityCountCmds': <Map<String, dynamic>>[cmdBody],
      },
      WsCommandType.alarmData => <String, dynamic>{
        'alarmDataCmds': <Map<String, dynamic>>[cmdBody],
      },
      WsCommandType.attributes => <String, dynamic>{
        'attrSubCmds': <Map<String, dynamic>>[cmdBody],
      },
      WsCommandType.timeseries => <String, dynamic>{
        'tsSubCmds': <Map<String, dynamic>>[cmdBody],
      },
      WsCommandType.timeseriesHistory => <String, dynamic>{
        'historyCmds': <Map<String, dynamic>>[cmdBody],
      },
      WsCommandType.alarmCount ||
      WsCommandType.alarmStatus ||
      WsCommandType.notifications ||
      WsCommandType.notificationsCount => null,
    };
  }

  Map<String, dynamic>? _buildUnsubscribeFrame(_ActiveSubscription removed) {
    if (!_useLegacyTelemetryEndpoint) {
      if (removed.type.isLegacyV1) {
        return <String, dynamic>{
          'cmds': <Map<String, dynamic>>[
            <String, dynamic>{
              ...removed.payload,
              'cmdId': removed.cmdId,
              'type': removed.type.wireValue,
              'unsubscribe': true,
            },
          ],
        };
      }
      if (removed.type.unsubscribeWire != null) {
        return <String, dynamic>{
          'cmds': <Map<String, dynamic>>[
            <String, dynamic>{
              'cmdId': removed.cmdId,
              'type': removed.type.unsubscribeWire,
            },
          ],
        };
      }
      return null;
    }

    return switch (removed.type) {
      WsCommandType.entityData => <String, dynamic>{
        'entityDataUnsubscribeCmds': <Map<String, dynamic>>[
          <String, dynamic>{'cmdId': removed.cmdId},
        ],
      },
      WsCommandType.entityCount => <String, dynamic>{
        'entityCountUnsubscribeCmds': <Map<String, dynamic>>[
          <String, dynamic>{'cmdId': removed.cmdId},
        ],
      },
      WsCommandType.alarmData => <String, dynamic>{
        'alarmDataUnsubscribeCmds': <Map<String, dynamic>>[
          <String, dynamic>{'cmdId': removed.cmdId},
        ],
      },
      WsCommandType.attributes => <String, dynamic>{
        'attrSubCmds': <Map<String, dynamic>>[
          <String, dynamic>{
            ...removed.payload,
            'cmdId': removed.cmdId,
            'unsubscribe': true,
          },
        ],
      },
      WsCommandType.timeseries => <String, dynamic>{
        'tsSubCmds': <Map<String, dynamic>>[
          <String, dynamic>{
            ...removed.payload,
            'cmdId': removed.cmdId,
            'unsubscribe': true,
          },
        ],
      },
      WsCommandType.timeseriesHistory ||
      WsCommandType.alarmCount ||
      WsCommandType.alarmStatus ||
      WsCommandType.notifications ||
      WsCommandType.notificationsCount => null,
    };
  }

  void _sendJson(Map<String, dynamic> payload) {
    final sink = _channel?.sink;
    if (sink == null) return;
    sink.add(jsonEncode(payload));
  }

  Future<void> _closeSocketOnly() async {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    await _socketSub?.cancel();
    _socketSub = null;
    final ch = _channel;
    _channel = null;
    if (ch != null) {
      await ch.sink.close();
    }
  }

  void _setState(WsConnectionState next) {
    if (_currentState == next || _stateController.isClosed) return;
    _currentState = next;
    _stateController.add(next);
  }
}

/// Merges initial `data.data` and incremental `update` frames from an
/// `ENTITY_DATA` WebSocket stream, preserving untouched keys and guarding
/// against out-of-order older timestamps.
Map<String, Map<String, TbTsPoint>> mergeEntityDataUpdates({
  required Map<String, Map<String, TbTsPoint>> current,
  required Map<String, dynamic> frame,
}) {
  final next = <String, Map<String, TbTsPoint>>{
    for (final entry in current.entries)
      entry.key: Map<String, TbTsPoint>.from(entry.value),
  };

  final rows = <dynamic>[
    ...((frame['data'] as Map<String, dynamic>?)?['data'] as List<dynamic>? ??
        const []),
    ...(frame['update'] as List<dynamic>? ?? const []),
  ];

  for (final item in rows) {
    if (item is! Map<String, dynamic>) continue;
    final entityId =
        (item['entityId'] as Map<String, dynamic>?)?['id'] as String?;
    if (entityId == null || entityId.isEmpty) continue;

    final latest = item['latest'] as Map<String, dynamic>?;
    if (latest == null) continue;

    final entityMap = next.putIfAbsent(entityId, () => <String, TbTsPoint>{});
    for (final scopeEntry in latest.values) {
      if (scopeEntry is! Map<String, dynamic>) continue;
      for (final kv in scopeEntry.entries) {
        if (kv.value is! Map<String, dynamic>) continue;
        final incoming = TbTsPoint.fromJson(kv.value as Map<String, dynamic>);
        final existing = entityMap[kv.key];
        if (existing == null || incoming.ts >= existing.ts) {
          entityMap[kv.key] = incoming;
        }
      }
    }
  }

  return next;
}
