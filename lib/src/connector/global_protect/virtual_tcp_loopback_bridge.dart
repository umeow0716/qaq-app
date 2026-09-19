import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'virtual_byte_socket.dart';

/// Adapts an in-process virtual TCP byte stream to a real loopback [Socket].
///
/// This exists because dart:io TLS can only be layered on a real RawSocket.
/// The listener is bound to 127.0.0.1 on an ephemeral port and accepts exactly
/// one connection. No traffic is exposed to the LAN and no HTTP/SOCKS protocol
/// is involved.
class VirtualTcpLoopbackBridge {
  VirtualTcpLoopbackBridge._({
    required this.socket,
    required this._virtualSocket,
    required this._server,
    required this._peer,
  });

  final Socket socket;
  final VirtualByteSocket _virtualSocket;
  final ServerSocket _server;
  final Socket _peer;

  StreamSubscription<Uint8List>? _virtualSubscription;
  StreamSubscription<Uint8List>? _peerSubscription;
  bool _closed = false;

  static Future<VirtualTcpLoopbackBridge> attach(
    VirtualByteSocket virtualSocket, {
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final server = await ServerSocket.bind(
      InternetAddress.loopbackIPv4,
      0,
      shared: false,
    );

    final peerCompleter = Completer<Socket>();
    late final StreamSubscription<Socket> acceptSubscription;
    acceptSubscription = server.listen(
      (peer) {
        if (!peerCompleter.isCompleted) {
          peerCompleter.complete(peer);
        } else {
          peer.destroy();
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        if (!peerCompleter.isCompleted) {
          peerCompleter.completeError(error, stackTrace);
        }
      },
    );

    Socket? client;
    Socket? peer;
    try {
      client = await Socket.connect(
        InternetAddress.loopbackIPv4,
        server.port,
        timeout: timeout,
      );
      peer = await peerCompleter.future.timeout(timeout);
      await acceptSubscription.cancel();
      await server.close();

      final bridge = VirtualTcpLoopbackBridge._(
        socket: client,
        virtualSocket: virtualSocket,
        server: server,
        peer: peer,
      );
      bridge._startRelay();
      return bridge;
    } catch (_) {
      await acceptSubscription.cancel();
      client?.destroy();
      peer?.destroy();
      await server.close();
      rethrow;
    }
  }

  void _startRelay() {
    _peerSubscription = _peer.listen(
      (data) {
        unawaited(_writeVirtual(Uint8List.fromList(data)));
      },
      onError: (Object error, StackTrace stackTrace) {
        unawaited(close());
      },
      onDone: () {
        unawaited(close());
      },
      cancelOnError: true,
    );

    _virtualSubscription = _virtualSocket.stream.listen(
      (data) {
        if (_closed) return;
        _peer.add(data);
      },
      onError: (Object error, StackTrace stackTrace) {
        _peer.destroy();
        unawaited(close());
      },
      onDone: () {
        unawaited(_peer.close());
      },
      cancelOnError: true,
    );
  }

  Future<void> _writeVirtual(Uint8List data) async {
    if (_closed || data.isEmpty) return;
    try {
      await _virtualSocket.write(data);
    } catch (_) {
      await close();
    }
  }

  Future<void> close({bool closeVirtualSocket = true}) async {
    if (_closed) return;
    _closed = true;

    await _peerSubscription?.cancel();
    await _virtualSubscription?.cancel();
    socket.destroy();
    _peer.destroy();
    await _server.close();

    if (closeVirtualSocket) {
      await _virtualSocket.close();
    }
  }
}
