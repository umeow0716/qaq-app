import 'dart:async';

import 'global_protect_models.dart';

enum GlobalProtectSessionState { disconnected, connecting, connected, reconnecting, disconnecting, disposed }

typedef GlobalProtectConnectCallback = Future<GlobalProtectConnection> Function();
typedef GlobalProtectDisconnectCallback = Future<void> Function(GlobalProtectConnection connection);
typedef GlobalProtectConnectionEvents = Stream<void> Function(GlobalProtectConnection connection);

class GlobalProtectSessionSnapshot {
  const GlobalProtectSessionSnapshot({required this.state, this.connection, this.error, this.stackTrace});

  final GlobalProtectSessionState state;
  final GlobalProtectConnection? connection;
  final Object? error;
  final StackTrace? stackTrace;

  bool get isConnected => state == GlobalProtectSessionState.connected && connection != null;
}

class GlobalProtectSessionManager {
  factory GlobalProtectSessionManager({
    required GlobalProtectConnectCallback connect,
    GlobalProtectDisconnectCallback? disconnect,
    GlobalProtectConnectionEvents? connectionEvents,
  }) => GlobalProtectSessionManager._(connect: connect, disconnect: disconnect, connectionEvents: connectionEvents);

  GlobalProtectSessionManager._({
    required this._connect,
    GlobalProtectDisconnectCallback? disconnect,
    GlobalProtectConnectionEvents? connectionEvents,
  }) : _disconnect = disconnect ?? _defaultDisconnect,
       _connectionEvents = connectionEvents ?? _defaultConnectionEvents;

  final GlobalProtectConnectCallback _connect;
  final GlobalProtectDisconnectCallback _disconnect;
  final GlobalProtectConnectionEvents _connectionEvents;
  final StreamController<GlobalProtectSessionSnapshot> _snapshots =
      StreamController<GlobalProtectSessionSnapshot>.broadcast();

  GlobalProtectSessionSnapshot _snapshot = const GlobalProtectSessionSnapshot(
    state: GlobalProtectSessionState.disconnected,
  );
  Future<GlobalProtectConnection>? _connectInFlight;
  StreamSubscription<void>? _connectionSubscription;
  int _generation = 0;

  Stream<GlobalProtectSessionSnapshot> get snapshots => _snapshots.stream;
  GlobalProtectSessionSnapshot get snapshot => _snapshot;
  GlobalProtectSessionState get state => _snapshot.state;
  GlobalProtectConnection? get connection => _snapshot.connection;
  bool get isConnected => _snapshot.isConnected;

  Future<GlobalProtectConnection> ensureConnected() {
    _throwIfDisposed();

    final current = _snapshot.connection;
    if (_snapshot.state == GlobalProtectSessionState.connected && current != null) {
      return Future<GlobalProtectConnection>.value(current);
    }

    final inFlight = _connectInFlight;
    if (inFlight != null) return inFlight;

    return _startConnect(reconnecting: false);
  }

  Future<GlobalProtectConnection> reconnect() async {
    _throwIfDisposed();

    final inFlight = _connectInFlight;
    if (inFlight != null) return inFlight;

    await _disconnectCurrent(emitDisconnected: false);
    return _startConnect(reconnecting: true);
  }

  Future<void> disconnect() async {
    _throwIfDisposed();
    _generation++;
    _connectInFlight = null;
    await _disconnectCurrent(emitDisconnected: true);
  }

  Future<void> dispose() async {
    if (_snapshot.state == GlobalProtectSessionState.disposed) return;

    _generation++;
    _connectInFlight = null;
    await _disconnectCurrent(emitDisconnected: false);
    _setSnapshot(const GlobalProtectSessionSnapshot(state: GlobalProtectSessionState.disposed));
    await _snapshots.close();
  }

  Future<GlobalProtectConnection> _startConnect({required bool reconnecting}) {
    final generation = ++_generation;
    _setSnapshot(
      GlobalProtectSessionSnapshot(
        state: reconnecting ? GlobalProtectSessionState.reconnecting : GlobalProtectSessionState.connecting,
      ),
    );

    final future = _performConnect(generation);
    _connectInFlight = future;
    unawaited(
      future.then<void>(
        (_) => _clearConnectInFlight(future),
        onError: (Object _, StackTrace _) => _clearConnectInFlight(future),
      ),
    );
    return future;
  }

  Future<GlobalProtectConnection> _performConnect(int generation) async {
    try {
      final newConnection = await _connect();
      if (_snapshot.state == GlobalProtectSessionState.disposed || generation != _generation) {
        await _disconnect(newConnection);
        throw StateError('GlobalProtect connection was superseded before it became active.');
      }

      await _connectionSubscription?.cancel();
      _connectionSubscription = _connectionEvents(newConnection).listen(
        (_) {},
        onError: (Object error, StackTrace stackTrace) {
          _handleConnectionEnded(newConnection, error: error, stackTrace: stackTrace);
        },
        onDone: () {
          _handleConnectionEnded(newConnection);
        },
      );

      _setSnapshot(GlobalProtectSessionSnapshot(state: GlobalProtectSessionState.connected, connection: newConnection));
      return newConnection;
    } catch (error, stackTrace) {
      if (generation == _generation && _snapshot.state != GlobalProtectSessionState.disposed) {
        _setSnapshot(
          GlobalProtectSessionSnapshot(
            state: GlobalProtectSessionState.disconnected,
            error: error,
            stackTrace: stackTrace,
          ),
        );
      }
      rethrow;
    }
  }

  Future<void> _disconnectCurrent({required bool emitDisconnected}) async {
    final current = _snapshot.connection;
    await _connectionSubscription?.cancel();
    _connectionSubscription = null;

    if (current != null) {
      _setSnapshot(GlobalProtectSessionSnapshot(state: GlobalProtectSessionState.disconnecting, connection: current));
      await _disconnect(current);
    }

    if (emitDisconnected && _snapshot.state != GlobalProtectSessionState.disposed) {
      _setSnapshot(const GlobalProtectSessionSnapshot(state: GlobalProtectSessionState.disconnected));
    }
  }

  void _handleConnectionEnded(GlobalProtectConnection endedConnection, {Object? error, StackTrace? stackTrace}) {
    if (_snapshot.state != GlobalProtectSessionState.connected || !identical(_snapshot.connection, endedConnection)) {
      return;
    }

    _connectionSubscription = null;
    _setSnapshot(
      GlobalProtectSessionSnapshot(state: GlobalProtectSessionState.disconnected, error: error, stackTrace: stackTrace),
    );
    unawaited(_disconnect(endedConnection).catchError((Object _, StackTrace _) {}));
  }

  void _clearConnectInFlight(Future<GlobalProtectConnection> future) {
    if (identical(_connectInFlight, future)) {
      _connectInFlight = null;
    }
  }

  void _setSnapshot(GlobalProtectSessionSnapshot next) {
    _snapshot = next;
    if (!_snapshots.isClosed) _snapshots.add(next);
  }

  void _throwIfDisposed() {
    if (_snapshot.state == GlobalProtectSessionState.disposed) {
      throw StateError('GlobalProtectSessionManager is disposed.');
    }
  }

  static Future<void> _defaultDisconnect(GlobalProtectConnection connection) => connection.transport.close();

  static Stream<void> _defaultConnectionEvents(GlobalProtectConnection connection) =>
      connection.transport.packets.map<void>((_) {});
}
