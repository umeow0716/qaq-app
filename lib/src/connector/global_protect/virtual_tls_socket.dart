import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'virtual_byte_socket.dart';
import 'virtual_tcp_loopback_bridge.dart';

/// TLS over a [VirtualByteSocket] without requiring a custom TLS implementation.
///
/// dart:io's TLS engine requires a real OS socket, so this class creates a
/// private 127.0.0.1 byte bridge and upgrades its client side with
/// [SecureSocket.secure]. The [host] argument remains the real remote hostname,
/// so SNI and certificate verification are performed for that hostname rather
/// than 127.0.0.1.
class VirtualTlsSocket {
  VirtualTlsSocket._(this._secureSocket, this._bridge);

  final SecureSocket _secureSocket;
  final VirtualTcpLoopbackBridge _bridge;
  bool _closed = false;

  SecureSocket get socket => _secureSocket;
  Stream<Uint8List> get stream => _secureSocket;
  String? get selectedProtocol => _secureSocket.selectedProtocol;
  X509Certificate? get peerCertificate => _secureSocket.peerCertificate;

  static Future<VirtualTlsSocket> secure(
    VirtualByteSocket virtualSocket, {
    required String host,
    SecurityContext? context,
    bool Function(X509Certificate certificate)? onBadCertificate,
    List<String>? supportedProtocols,
    Duration bridgeTimeout = const Duration(seconds: 5),
    Duration handshakeTimeout = const Duration(seconds: 15),
  }) async {
    final bridge = await VirtualTcpLoopbackBridge.attach(virtualSocket, timeout: bridgeTimeout);

    try {
      final secureSocket =
          await SecureSocket.secure(
            bridge.socket,
            host: host,
            context: context,
            onBadCertificate: onBadCertificate,
            supportedProtocols: supportedProtocols,
          ).timeout(
            handshakeTimeout,
            onTimeout: () => throw TimeoutException('TLS handshake with $host timed out after $handshakeTimeout.'),
          );
      return VirtualTlsSocket._(secureSocket, bridge);
    } catch (_) {
      await bridge.close();
      rethrow;
    }
  }

  void add(List<int> data) => _secureSocket.add(data);

  Future<void> flush() => _secureSocket.flush();

  Future<void> write(Uint8List data) async {
    if (_closed) throw StateError('Virtual TLS socket is closed.');
    _secureSocket.add(data);
    await _secureSocket.flush();
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    try {
      await _secureSocket.close();
    } finally {
      await _bridge.close();
    }
  }
}
