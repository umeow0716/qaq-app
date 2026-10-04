import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'global_protect_app_session.dart';
import 'global_protect_debug.dart';
import 'virtual_byte_socket.dart';
import 'virtual_tcp_socket.dart';

/// A loopback HTTP proxy used as an adapter between platform WebView proxy
/// configuration and the app's userspace GlobalProtect TCP implementation.
///
/// Requests that enter this proxy route only the configured VPN target hosts
/// through GlobalProtect; other destinations can still be forwarded directly.
/// Windows normally avoids the bridge entirely for non-iStudy hosts via PAC.
/// HTTPS remains end-to-end between WebView and the destination; CONNECT bytes
/// are forwarded without TLS interception or a custom CA.
class GlobalProtectWebViewProxyBridge {
  GlobalProtectWebViewProxyBridge._();

  static final GlobalProtectWebViewProxyBridge instance = GlobalProtectWebViewProxyBridge._();

  static const String windowsPacPath = '/qaq-webview-proxy.pac';
  static const Duration upstreamConnectTimeout = Duration(seconds: 20);

  ServerSocket? _server;
  StreamSubscription<Socket>? _serverSubscription;
  final Set<Socket> _clients = <Socket>{};
  Future<int>? _startInFlight;
  int _generation = 0;
  bool _vpnRoutingEnabled = false;

  bool get isRunning => _server != null;
  int? get port => _server?.port;
  bool get vpnRoutingEnabled => _vpnRoutingEnabled;

  Set<String> _vpnHosts = const <String>{};

  /// Starts the loopback listener without connecting GlobalProtect.
  ///
  /// Windows WebView2 proxy arguments are fixed when its process-wide
  /// environment is created. Windows therefore binds this listener before the
  /// first WebView exists, while iStudy traffic stays direct until
  /// [enableVpnRouting] is called.
  Future<int> ensureListening({required Iterable<String> vpnHosts}) {
    final normalizedVpnHosts = vpnHosts.map(_normalizeHost).where((host) => host.isNotEmpty).toSet();
    if (normalizedVpnHosts.isEmpty) {
      return Future<int>.error(ArgumentError.value(vpnHosts, 'vpnHosts', 'At least one VPN target host is required.'));
    }

    final existing = _server;
    if (existing != null) {
      if (!_sameHostSet(_vpnHosts, normalizedVpnHosts)) {
        return Future<int>.error(
          StateError('WebView GP proxy is already bound to $_vpnHosts, not $normalizedVpnHosts.'),
        );
      }
      return Future<int>.value(existing.port);
    }

    final inFlight = _startInFlight;
    if (inFlight != null) {
      if (_vpnHosts.isNotEmpty && !_sameHostSet(_vpnHosts, normalizedVpnHosts)) {
        return Future<int>.error(StateError('WebView GP proxy is starting for $_vpnHosts, not $normalizedVpnHosts.'));
      }
      return inFlight;
    }

    _vpnHosts = Set<String>.unmodifiable(normalizedVpnHosts);
    final generation = _generation;
    final future = _start(generation);
    _startInFlight = future;
    unawaited(
      future.then<void>(
        (_) => _clearStartFuture(future),
        onError: (Object _, StackTrace _) => _clearStartFuture(future, failed: true),
      ),
    );
    return future;
  }

  /// Starts the listener and enables GlobalProtect routing for iStudy.
  ///
  /// Android and Linux call this when they can install their native WebView
  /// proxy dynamically. Windows normally calls [ensureListening] earlier and
  /// enables VPN routing only after its access guard selects the VPN route.
  Future<int> ensureStarted({required Iterable<String> vpnHosts}) async {
    final port = await ensureListening(vpnHosts: vpnHosts);
    await enableVpnRouting();
    return port;
  }

  Future<void> enableVpnRouting() async {
    if (_vpnHosts.isEmpty) {
      throw StateError('WebView GP proxy listener must be started before enabling VPN routing.');
    }
    if (_vpnRoutingEnabled) return;

    GlobalProtectDebug.log('WebView proxy enabling GlobalProtect routing');
    await GlobalProtectAppSession.instance.ensureConnected();
    _vpnRoutingEnabled = true;
    GlobalProtectDebug.log('WebView proxy GlobalProtect routing enabled');
  }

  void disableVpnRouting() {
    if (!_vpnRoutingEnabled) return;
    _vpnRoutingEnabled = false;
    GlobalProtectDebug.log('WebView proxy GlobalProtect routing disabled');
  }

  Future<int> _start(int generation) async {
    GlobalProtectDebug.log('WebView loopback proxy listener start requested');
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0, shared: false);
    if (generation != _generation) {
      await server.close();
      throw StateError('WebView GP proxy start was superseded by a runtime reset.');
    }
    _server = server;
    _serverSubscription = server.listen(
      (client) {
        GlobalProtectDebug.log('WebView proxy accepted loopback client');
        _clients.add(client);
        unawaited(_serve(client));
      },
      onError: (Object error, StackTrace stackTrace) {
        GlobalProtectDebug.error('WebView proxy listener', error, stackTrace);
      },
    );
    GlobalProtectDebug.log('WebView loopback proxy listening on 127.0.0.1:${server.port}');
    return server.port;
  }

  void _clearStartFuture(Future<int> future, {bool failed = false}) {
    if (!identical(_startInFlight, future)) return;
    _startInFlight = null;
    if (failed && _server == null) _vpnHosts = const <String>{};
  }

  Future<void> _serve(Socket client) async {
    VirtualByteSocket? upstream;
    StreamSubscription<Uint8List>? upstreamSubscription;
    StreamSubscription<Uint8List>? clientSubscription;
    final initialBytes = BytesBuilder(copy: false);
    var forwarding = false;
    var closed = false;

    Future<void> closeBoth() async {
      if (closed) return;
      closed = true;
      await clientSubscription?.cancel();
      await upstreamSubscription?.cancel();
      if (upstream != null) {
        try {
          await upstream!.close();
        } catch (_) {}
      }
      client.destroy();
      _clients.remove(client);
    }

    Future<void> fail([Object? _]) async {
      if (!forwarding && !closed) {
        try {
          client.write('HTTP/1.1 502 Bad Gateway\r\nConnection: close\r\nContent-Length: 0\r\n\r\n');
          await client.flush();
        } catch (_) {}
      }
      await closeBoth();
    }

    clientSubscription = client.listen(
      (data) {
        if (closed) return;
        if (forwarding) {
          final socket = upstream;
          if (socket != null) {
            unawaited(
              socket.write(Uint8List.fromList(data)).catchError((Object error, StackTrace stack) {
                unawaited(fail(error));
              }),
            );
          }
          return;
        }

        initialBytes.add(data);
        if (initialBytes.length > 64 * 1024) {
          unawaited(fail(const FormatException('Proxy request headers are too large.')));
          return;
        }

        final buffered = initialBytes.toBytes();
        final headerEnd = _findHeaderEnd(buffered);
        if (headerEnd < 0) return;

        clientSubscription?.pause();
        unawaited(() async {
          try {
            final request = _ProxyRequest.parse(buffered, headerEnd);
            if (_isWindowsPacRequest(request)) {
              await _serveWindowsPac(client, clientSubscription);
              closed = true;
              _clients.remove(client);
              return;
            }
            GlobalProtectDebug.log(
              'WebView proxy request method=${request.isConnect ? 'CONNECT' : 'HTTP'} '
              'host=${request.host} port=${request.port}',
            );
            final useGlobalProtect = _shouldRouteThroughGlobalProtect(request.host);
            GlobalProtectDebug.log(
              'WebView proxy route host=${request.host} port=${request.port} '
              'via=${useGlobalProtect ? 'globalProtect' : 'direct'}',
            );
            upstream = useGlobalProtect
                ? await _connectVirtual(request.host, request.port)
                : await _connectDirect(request.host, request.port);
            upstreamSubscription = upstream!.stream.listen(
              (bytes) => client.add(bytes),
              onError: (Object error, StackTrace stack) => unawaited(fail(error)),
              onDone: () => unawaited(closeBoth()),
              cancelOnError: false,
            );

            if (request.isConnect) {
              client.write('HTTP/1.1 200 Connection Established\r\nProxy-Agent: QAQ-GP\r\n\r\n');
              await client.flush();
              if (request.remainder.isNotEmpty) {
                await upstream!.write(request.remainder);
              }
            } else {
              await upstream!.write(request.forwardBytes);
            }

            forwarding = true;
            clientSubscription?.resume();
          } catch (error, stackTrace) {
            GlobalProtectDebug.error('WebView proxy request', error, stackTrace);
            await fail(error);
          }
        }());
      },
      onError: (Object error, StackTrace stack) => unawaited(fail(error)),
      onDone: () => unawaited(closeBoth()),
      cancelOnError: false,
    );
  }

  bool _isWindowsPacRequest(_ProxyRequest request) {
    final server = _server;
    if (server == null || request.isConnect) return false;
    return request.host == InternetAddress.loopbackIPv4.address &&
        request.port == server.port &&
        request.target == windowsPacPath;
  }

  Future<void> _serveWindowsPac(Socket client, StreamSubscription<Uint8List>? clientSubscription) async {
    final vpnHosts = _vpnHosts;
    final server = _server;
    if (vpnHosts.isEmpty || server == null) {
      throw StateError('WebView PAC requested before the loopback proxy was ready.');
    }

    await clientSubscription?.cancel();
    final encodedHosts = jsonEncode(vpnHosts.toList(growable: false)..sort());
    final body = utf8.encode(
      'function FindProxyForURL(url, host) {\n'
      '  host = String(host || "").toLowerCase().replace(/\\.\$/, "");\n'
      '  const proxyHosts = $encodedHosts;\n'
      '  if (proxyHosts.indexOf(host) !== -1) return "PROXY 127.0.0.1:${server.port}";\n'
      '  return "DIRECT";\n'
      '}\n',
    );
    final headers = ascii.encode(
      'HTTP/1.1 200 OK\r\n'
      'Content-Type: application/x-ns-proxy-autoconfig; charset=utf-8\r\n'
      'Cache-Control: no-store, no-cache, must-revalidate\r\n'
      'Content-Length: ${body.length}\r\n'
      'Connection: close\r\n'
      '\r\n',
    );
    client.add(<int>[...headers, ...body]);
    await client.flush();
    await client.close();
    GlobalProtectDebug.log('served Windows WebView2 PAC for ${vpnHosts.join(',')}');
  }

  bool _shouldRouteThroughGlobalProtect(String host) {
    return _vpnRoutingEnabled && shouldRouteThroughGlobalProtect(host: host, vpnHosts: _vpnHosts);
  }

  static bool shouldRouteThroughGlobalProtect({required String host, required Iterable<String> vpnHosts}) {
    final normalizedHost = _normalizeHost(host);
    if (normalizedHost.isEmpty) return false;
    return vpnHosts.map(_normalizeHost).contains(normalizedHost);
  }

  static bool _sameHostSet(Set<String> left, Set<String> right) {
    return left.length == right.length && left.containsAll(right);
  }

  static String _normalizeHost(String host) {
    var value = host.trim().toLowerCase();
    while (value.endsWith('.')) {
      value = value.substring(0, value.length - 1);
    }
    return value;
  }

  Future<VirtualByteSocket> _connectDirect(String host, int port) async {
    GlobalProtectDebug.log('direct TCP connect -> $host:$port');
    final socket = await Socket.connect(host, port, timeout: upstreamConnectTimeout);
    GlobalProtectDebug.log('direct TCP connected -> ${socket.remoteAddress.address}:$port');
    return _DirectByteSocket(socket);
  }

  Future<VirtualByteSocket> _connectVirtual(String host, int port) async {
    GlobalProtectDebug.log('virtual TCP connect -> $host:$port');
    final appSession = GlobalProtectAppSession.instance;
    final connection = await appSession.ensureConnected();
    final localAddress = connection.config.ipAddress;
    if (localAddress == null || localAddress.isEmpty) {
      throw StateError('GlobalProtect did not provide an IPv4 tunnel address.');
    }

    final remoteAddress = await appSession.resolveIpv4(host);
    GlobalProtectDebug.log('resolved $host -> ${remoteAddress.address}; opening virtual TCP');
    final socket = await VirtualTcpSocket.connectIp(
      transport: connection.transport,
      localAddress: localAddress,
      remoteAddress: remoteAddress.address,
      remotePort: port,
      timeout: upstreamConnectTimeout,
      maxSegmentPayload: _payloadForMtu(connection.config.mtu),
    );
    GlobalProtectDebug.log('virtual TCP connected -> ${remoteAddress.address}:$port');
    return socket;
  }

  Future<void> close() async {
    _generation++;
    _startInFlight = null;
    if (_server != null) GlobalProtectDebug.log('closing WebView GP proxy bridge');
    final subscription = _serverSubscription;
    _serverSubscription = null;
    await subscription?.cancel();

    final server = _server;
    _server = null;
    _vpnHosts = const <String>{};
    _vpnRoutingEnabled = false;
    await server?.close();

    final clients = _clients.toList(growable: false);
    _clients.clear();
    for (final client in clients) {
      client.destroy();
    }
  }

  static int _payloadForMtu(int? mtu) {
    if (mtu == null || mtu <= 40) return 1200;
    final payload = mtu - 40;
    return payload < 1200 ? payload : 1200;
  }

  static int _findHeaderEnd(Uint8List bytes) {
    for (var i = 0; i + 3 < bytes.length; i++) {
      if (bytes[i] == 13 && bytes[i + 1] == 10 && bytes[i + 2] == 13 && bytes[i + 3] == 10) {
        return i + 4;
      }
    }
    return -1;
  }
}

class _DirectByteSocket implements VirtualByteSocket {
  _DirectByteSocket(this._socket);

  final Socket _socket;

  @override
  Stream<Uint8List> get stream => _socket;

  @override
  Future<void> write(Uint8List data) async {
    _socket.add(data);
    await _socket.flush();
  }

  @override
  Future<void> close({bool sendFin = true}) async {
    if (sendFin) {
      await _socket.close();
    } else {
      _socket.destroy();
    }
  }
}

class _ProxyRequest {
  const _ProxyRequest({
    required this.isConnect,
    required this.host,
    required this.port,
    required this.target,
    required this.forwardBytes,
    required this.remainder,
  });

  final bool isConnect;
  final String host;
  final int port;
  final String target;
  final Uint8List forwardBytes;
  final Uint8List remainder;

  factory _ProxyRequest.parse(Uint8List bytes, int headerEnd) {
    final headerBytes = Uint8List.sublistView(bytes, 0, headerEnd);
    final remainder = Uint8List.fromList(bytes.sublist(headerEnd));
    final headerText = latin1.decode(headerBytes, allowInvalid: false);
    final lines = headerText.split('\r\n');
    if (lines.isEmpty || lines.first.trim().isEmpty) {
      throw const FormatException('Missing HTTP proxy request line.');
    }

    final requestParts = lines.first.split(' ');
    if (requestParts.length < 3) throw const FormatException('Invalid HTTP proxy request line.');
    final method = requestParts[0].toUpperCase();
    final target = requestParts[1];

    if (method == 'CONNECT') {
      final authority = _parseAuthority(target, defaultPort: 443);
      return _ProxyRequest(
        isConnect: true,
        host: authority.$1,
        port: authority.$2,
        target: target,
        forwardBytes: Uint8List(0),
        remainder: remainder,
      );
    }

    Uri? absoluteUri;
    try {
      absoluteUri = Uri.parse(target);
    } catch (_) {}

    String host;
    int port;
    String originTarget = target;
    if (absoluteUri != null && absoluteUri.hasScheme && absoluteUri.host.isNotEmpty) {
      host = absoluteUri.host;
      port = absoluteUri.hasPort ? absoluteUri.port : (absoluteUri.scheme == 'https' ? 443 : 80);
      originTarget = absoluteUri.hasQuery
          ? '${absoluteUri.path.isEmpty ? '/' : absoluteUri.path}?${absoluteUri.query}'
          : (absoluteUri.path.isEmpty ? '/' : absoluteUri.path);
    } else {
      final hostHeader = lines.firstWhere((line) => line.toLowerCase().startsWith('host:'), orElse: () => '');
      if (hostHeader.isEmpty) throw const FormatException('HTTP proxy request has no Host header.');
      final authority = _parseAuthority(hostHeader.substring(5).trim(), defaultPort: 80);
      host = authority.$1;
      port = authority.$2;
    }

    final rewrittenLines = <String>['$method $originTarget ${requestParts.sublist(2).join(' ')}', ...lines.skip(1)];
    final rewrittenHeader = latin1.encode(rewrittenLines.join('\r\n'));
    return _ProxyRequest(
      isConnect: false,
      host: host,
      port: port,
      target: originTarget,
      forwardBytes: Uint8List.fromList(<int>[...rewrittenHeader, ...remainder]),
      remainder: Uint8List(0),
    );
  }

  static (String, int) _parseAuthority(String value, {required int defaultPort}) {
    final trimmed = value.trim();
    final colon = trimmed.lastIndexOf(':');
    if (colon > 0 && colon < trimmed.length - 1) {
      final candidatePort = int.tryParse(trimmed.substring(colon + 1));
      if (candidatePort != null) {
        return (trimmed.substring(0, colon), candidatePort);
      }
    }
    if (trimmed.isEmpty) throw const FormatException('Proxy target host is empty.');
    return (trimmed, defaultPort);
  }
}
