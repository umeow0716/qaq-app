import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'global_protect_app_session.dart';
import 'global_protect_debug.dart';
import 'virtual_byte_socket.dart';
import 'virtual_tcp_socket.dart';

/// A loopback HTTP proxy used only as an adapter between Android WebView's
/// ProxyOverride API and the app's userspace GlobalProtect TCP implementation.
///
/// HTTPS remains end-to-end between WebView and the destination. CONNECT bytes
/// are forwarded without TLS interception or a custom CA.
class GlobalProtectWebViewProxyBridge {
  GlobalProtectWebViewProxyBridge._();

  static final GlobalProtectWebViewProxyBridge instance = GlobalProtectWebViewProxyBridge._();

  ServerSocket? _server;
  StreamSubscription<Socket>? _serverSubscription;
  final Set<Socket> _clients = <Socket>{};
  Future<int>? _startInFlight;
  int _generation = 0;

  bool get isRunning => _server != null;
  int? get port => _server?.port;

  Future<int> ensureStarted() {
    final existing = _server;
    if (existing != null) return Future<int>.value(existing.port);

    final inFlight = _startInFlight;
    if (inFlight != null) return inFlight;

    final generation = _generation;
    final future = _start(generation);
    _startInFlight = future;
    unawaited(
      future.then<void>(
        (_) => _clearStartFuture(future),
        onError: (Object _, StackTrace _) => _clearStartFuture(future),
      ),
    );
    return future;
  }

  Future<int> _start(int generation) async {
    GlobalProtectDebug.log('WebView bridge start requested');
    await GlobalProtectAppSession.instance.ensureConnected();
    GlobalProtectDebug.log('GP session connected; binding WebView loopback proxy');
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

  void _clearStartFuture(Future<int> future) {
    if (identical(_startInFlight, future)) _startInFlight = null;
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
            GlobalProtectDebug.log(
              'WebView proxy request method=${request.isConnect ? 'CONNECT' : 'HTTP'} '
              'host=${request.host} port=${request.port}',
            );
            upstream = await _connectVirtual(request.host, request.port);
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
      timeout: const Duration(seconds: 10),
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

class _ProxyRequest {
  const _ProxyRequest({
    required this.isConnect,
    required this.host,
    required this.port,
    required this.forwardBytes,
    required this.remainder,
  });

  final bool isConnect;
  final String host;
  final int port;
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
