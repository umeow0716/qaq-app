import 'dart:async';
import 'dart:io';

import 'global_protect_transport.dart';
import 'global_protect_models.dart';
import 'virtual_byte_socket.dart';
import 'virtual_tcp_loopback_bridge.dart';
import 'virtual_tcp_socket.dart';
import 'virtual_tls_socket.dart';

typedef GlobalProtectHostResolver = Future<InternetAddress> Function(String host);
typedef GlobalProtectVirtualSocketDialer = Future<VirtualByteSocket> Function(
  InternetAddress remoteAddress,
  int remotePort,
);

/// Builds a dart:io [HttpClient] whose TCP connections are carried through a
/// GlobalProtect data transport instead of Android's normal routing table.
///
/// HTTP parsing, cookies, redirects, compression, and connection reuse remain
/// owned by dart:io. This class only replaces socket creation.
class GlobalProtectHttpClient {
  GlobalProtectHttpClient({
    required GlobalProtectTransport transport,
    required String localAddress,
    GlobalProtectHostResolver? resolver,
    GlobalProtectVirtualSocketDialer? socketDialer,
    SecurityContext? securityContext,
    Duration tcpConnectTimeout = const Duration(seconds: 8),
    Duration bridgeTimeout = const Duration(seconds: 5),
    Duration tlsHandshakeTimeout = const Duration(seconds: 15),
    int maxSegmentPayload = 1200,
    VirtualTcpTrace? tcpTrace,
  })  : _transport = transport,
        _localAddress = localAddress,
        _resolver = resolver ?? _defaultResolver,
        _socketDialer = socketDialer,
        _securityContext = securityContext,
        _tcpConnectTimeout = tcpConnectTimeout,
        _bridgeTimeout = bridgeTimeout,
        _tlsHandshakeTimeout = tlsHandshakeTimeout,
        _maxSegmentPayload = maxSegmentPayload,
        _tcpTrace = tcpTrace,
        client = HttpClient(context: securityContext) {
    client.findProxy = (_) => 'DIRECT';
    client.connectionFactory = _createConnection;
  }

  factory GlobalProtectHttpClient.fromConnection(
    GlobalProtectConnection connection, {
    GlobalProtectHostResolver? resolver,
    GlobalProtectVirtualSocketDialer? socketDialer,
    SecurityContext? securityContext,
    Duration tcpConnectTimeout = const Duration(seconds: 8),
    Duration bridgeTimeout = const Duration(seconds: 5),
    Duration tlsHandshakeTimeout = const Duration(seconds: 15),
    int? maxSegmentPayload,
    VirtualTcpTrace? tcpTrace,
  }) {
    final localAddress = connection.config.ipAddress;
    if (localAddress == null || localAddress.isEmpty) {
      throw StateError('GlobalProtect did not provide an IPv4 tunnel address.');
    }
    return GlobalProtectHttpClient(
      transport: connection.transport,
      localAddress: localAddress,
      resolver: resolver,
      socketDialer: socketDialer,
      securityContext: securityContext,
      tcpConnectTimeout: tcpConnectTimeout,
      bridgeTimeout: bridgeTimeout,
      tlsHandshakeTimeout: tlsHandshakeTimeout,
      maxSegmentPayload: maxSegmentPayload ?? _payloadForMtu(connection.config.mtu),
      tcpTrace: tcpTrace,
    );
  }

  final GlobalProtectTransport _transport;
  final String _localAddress;
  final GlobalProtectHostResolver _resolver;
  final GlobalProtectVirtualSocketDialer? _socketDialer;
  final SecurityContext? _securityContext;
  final Duration _tcpConnectTimeout;
  final Duration _bridgeTimeout;
  final Duration _tlsHandshakeTimeout;
  final int _maxSegmentPayload;
  final VirtualTcpTrace? _tcpTrace;
  final Set<VirtualTlsSocket> _tlsSockets = <VirtualTlsSocket>{};

  final HttpClient client;
  bool _closed = false;

  Future<ConnectionTask<Socket>> _createConnection(
    Uri uri,
    String? proxyHost,
    int? proxyPort,
  ) async {
    if (_closed) {
      throw StateError('GlobalProtectHttpClient is closed.');
    }
    if (proxyHost != null || proxyPort != null) {
      throw UnsupportedError('Proxy connections are not supported inside the GlobalProtect data transport.');
    }

    if (uri.scheme != 'http' && uri.scheme != 'https') {
      throw UnsupportedError('Only HTTP and HTTPS are supported through GlobalProtectHttpClient.');
    }
    final port = uri.port == 0 ? (uri.scheme == 'https' ? 443 : 80) : uri.port;
    final remoteAddress = await _resolver(uri.host);
    if (remoteAddress.type != InternetAddressType.IPv4) {
      throw UnsupportedError('GlobalProtectHttpClient currently supports IPv4 destinations only.');
    }

    final virtualSocket = _socketDialer == null
        ? await VirtualTcpSocket.connectIp(
            transport: _transport,
            localAddress: _localAddress,
            remoteAddress: remoteAddress.address,
            remotePort: port,
            timeout: _tcpConnectTimeout,
            maxSegmentPayload: _maxSegmentPayload,
            trace: _tcpTrace,
          )
        : await _socketDialer(remoteAddress, port);

    if (uri.scheme == 'https') {
      final tls = await VirtualTlsSocket.secure(
        virtualSocket,
        host: uri.host,
        context: _securityContext,
        bridgeTimeout: _bridgeTimeout,
        handshakeTimeout: _tlsHandshakeTimeout,
      );
      _trackTls(tls);
      return ConnectionTask.fromSocket(Future<Socket>.value(tls.socket), () {
        unawaited(tls.close());
      });
    }

    // HttpClient.connectionFactory requires a real Socket. For plain HTTP we
    // therefore use the same loopback bridge without applying TLS.
    final bridge = await VirtualTcpLoopbackBridge.attach(virtualSocket, timeout: _bridgeTimeout);
    final socket = bridge.socket;
    unawaited(socket.done.whenComplete(() => bridge.close()));
    return ConnectionTask.fromSocket(Future<Socket>.value(socket), () {
      unawaited(bridge.close());
    });
  }

  void _trackTls(VirtualTlsSocket tls) {
    _tlsSockets.add(tls);
    unawaited(
      tls.socket.done.whenComplete(() async {
        _tlsSockets.remove(tls);
        await tls.close();
      }),
    );
  }

  Future<void> close({bool force = false}) async {
    if (_closed) return;
    _closed = true;

    // Stop HttpClient from creating/retaining connections first, then wait for
    // every virtual TLS socket to finish closing while the GP data transport is still
    // alive. Callers that own the connection should await this before disposing
    // their GlobalProtectSessionManager.
    client.close(force: force);
    final sockets = _tlsSockets.toList(growable: false);
    _tlsSockets.clear();
    await Future.wait<void>(
      sockets.map((socket) => socket.close()),
      eagerError: false,
    );
  }

  static int _payloadForMtu(int? mtu) {
    // Reserve 20 bytes for IPv4 + 20 bytes for the minimum TCP header. Keep a
    // conservative ceiling because GP deployments may add encapsulation below
    // the virtual IP layer.
    if (mtu == null || mtu <= 40) return 1200;
    final payload = mtu - 40;
    return payload < 1200 ? payload : 1200;
  }

  static Future<InternetAddress> _defaultResolver(String host) async {
    final literal = InternetAddress.tryParse(host);
    if (literal != null) return literal;

    final addresses = await InternetAddress.lookup(host, type: InternetAddressType.IPv4);
    if (addresses.isEmpty) {
      throw SocketException('No IPv4 address found for $host');
    }
    return addresses.first;
  }
}
