import 'dart:async';
import 'dart:convert';

import 'package:stream_channel/stream_channel.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// Test [WebSocketSink] recording all client-sent payloads.
class FakeWebSocketSink implements WebSocketSink {
  FakeWebSocketSink(this._onAdd, this._onClose);

  final void Function(dynamic data) _onAdd;
  final Future<void> Function(int? closeCode, String? closeReason) _onClose;
  final Completer<void> _done = Completer<void>();

  bool isClosed = false;

  @override
  void add(dynamic data) {
    if (isClosed) return;
    _onAdd(data);
  }

  @override
  void addError(Object error, [StackTrace? stackTrace]) {}

  @override
  Future<void> addStream(Stream<dynamic> stream) async {
    await for (final event in stream) {
      add(event);
    }
  }

  @override
  Future<void> close([int? closeCode, String? closeReason]) async {
    if (isClosed) return;
    isClosed = true;
    await _onClose(closeCode, closeReason);
    if (!_done.isCompleted) _done.complete();
  }

  @override
  Future<void> get done => _done.future;
}

/// Fake [WebSocketChannel] exposing deterministic server push and sent-frame inspection.
class FakeWebSocketChannel extends StreamChannelMixin<dynamic>
    implements WebSocketChannel {
  FakeWebSocketChannel({Future<void>? readyFuture})
    : _readyFuture = readyFuture ?? Future<void>.value() {
    _sink = FakeWebSocketSink((data) => sentMessages.add(data.toString()), (
      code,
      reason,
    ) async {
      _closeCode = code;
      _closeReason = reason;
      if (!_incoming.isClosed) {
        await _incoming.close();
      }
    });
  }

  final Future<void> _readyFuture;
  final StreamController<dynamic> _incoming =
      StreamController<dynamic>.broadcast();
  late final FakeWebSocketSink _sink;

  final List<String> sentMessages = [];
  int? _closeCode;
  String? _closeReason;

  List<Map<String, dynamic>> get decodedSentFrames => sentMessages
      .map((s) => jsonDecode(s))
      .whereType<Map<String, dynamic>>()
      .toList(growable: false);

  /// Simulates a JSON or raw message arriving from the ThingsBoard WS server.
  void pushServerJson(Map<String, dynamic> payload) {
    if (!_incoming.isClosed) {
      _incoming.add(jsonEncode(payload));
    }
  }

  /// Simulates server closing the socket (e.g. network drop or close code 1007).
  Future<void> simulateServerClose([int? code, String? reason]) async {
    _closeCode = code;
    _closeReason = reason;
    if (!_incoming.isClosed) {
      await _incoming.close();
    }
  }

  /// Simulates a stream error on the underlying socket.
  void simulateError(Object error) {
    if (!_incoming.isClosed) {
      _incoming.addError(error);
    }
  }

  @override
  int? get closeCode => _closeCode;

  @override
  String? get closeReason => _closeReason;

  @override
  String? get protocol => null;

  @override
  Future<void> get ready => _readyFuture;

  @override
  WebSocketSink get sink => _sink;

  @override
  Stream<dynamic> get stream => _incoming.stream;
}
