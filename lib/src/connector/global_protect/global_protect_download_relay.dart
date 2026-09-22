import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'global_protect_app_session.dart';
import 'global_protect_debug.dart';

class GlobalProtectDownloadRelay {
  GlobalProtectDownloadRelay._();

  static final GlobalProtectDownloadRelay instance = GlobalProtectDownloadRelay._();
  static const _ticketTtl = Duration(hours: 6);
  static final Random _random = Random.secure();

  HttpServer? _server;
  Future<int>? _startInFlight;
  final Map<String, _DownloadTicket> _tickets = <String, _DownloadTicket>{};

  Future<Uri> createDownloadUri({
    required Uri target,
    required String allowedHost,
    String? cookieHeader,
    String? userAgent,
    String? referer,
  }) async {
    if ((target.scheme != 'http' && target.scheme != 'https') ||
        target.host.toLowerCase() != allowedHost.toLowerCase()) {
      throw ArgumentError.value(target, 'target', 'Download relay only accepts the configured iStudy host.');
    }

    final port = await _ensureStarted();
    _removeExpiredTickets();
    final token = _newToken();
    _tickets[token] = _DownloadTicket(
      target: target,
      cookieHeader: cookieHeader,
      userAgent: userAgent,
      referer: referer,
    );
    GlobalProtectDebug.log('created GP download relay ticket for ${target.host}');
    return Uri(scheme: 'http', host: '127.0.0.1', port: port, path: '/download/$token');
  }

  Future<int> _ensureStarted() {
    final server = _server;
    if (server != null) return Future<int>.value(server.port);
    final inFlight = _startInFlight;
    if (inFlight != null) return inFlight;

    final future = _start();
    _startInFlight = future;
    unawaited(
      future.then<void>(
        (_) {
          if (identical(_startInFlight, future)) _startInFlight = null;
        },
        onError: (Object _, StackTrace _) {
          if (identical(_startInFlight, future)) _startInFlight = null;
        },
      ),
    );
    return future;
  }

  Future<int> _start() async {
    await GlobalProtectAppSession.instance.ensureConnected();
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0, shared: false);
    server.autoCompress = false;
    _server = server;
    server.listen(
      (request) => unawaited(_serve(request)),
      onError: (Object error, StackTrace stackTrace) {
        GlobalProtectDebug.error('GP download relay listener', error, stackTrace);
      },
    );
    GlobalProtectDebug.log('GP download relay listening on 127.0.0.1:${server.port}');
    return server.port;
  }

  Future<void> _serve(HttpRequest request) async {
    final response = request.response;
    var responseStarted = false;

    try {
      final remote = request.connectionInfo?.remoteAddress;
      if (remote == null || !remote.isLoopback) {
        response.statusCode = HttpStatus.forbidden;
        await response.close();
        return;
      }
      if (request.method != 'GET' && request.method != 'HEAD') {
        response.statusCode = HttpStatus.methodNotAllowed;
        await response.close();
        return;
      }

      _removeExpiredTickets();
      final segments = request.uri.pathSegments;
      if (segments.length != 2 || segments.first != 'download') {
        response.statusCode = HttpStatus.notFound;
        await response.close();
        return;
      }
      final ticket = _tickets[segments[1]];
      if (ticket == null) {
        response.statusCode = HttpStatus.gone;
        await response.close();
        return;
      }
      ticket.touch();

      final gpHttp = await GlobalProtectAppSession.instance.ensureHttpClient();
      gpHttp.client.autoUncompress = false;
      final upstreamRequest = await gpHttp.client.openUrl(request.method, ticket.target);
      upstreamRequest.followRedirects = true;
      upstreamRequest.maxRedirects = 5;
      upstreamRequest.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');

      for (final header in const <String>[
        HttpHeaders.rangeHeader,
        HttpHeaders.ifRangeHeader,
        HttpHeaders.ifNoneMatchHeader,
        HttpHeaders.ifModifiedSinceHeader,
        HttpHeaders.acceptHeader,
      ]) {
        final value = request.headers.value(header);
        if (value != null) upstreamRequest.headers.set(header, value);
      }
      if (ticket.userAgent?.isNotEmpty == true) {
        upstreamRequest.headers.set(HttpHeaders.userAgentHeader, ticket.userAgent!);
      }
      if (ticket.cookieHeader?.isNotEmpty == true) {
        upstreamRequest.headers.set(HttpHeaders.cookieHeader, ticket.cookieHeader!);
      }
      if (ticket.referer?.isNotEmpty == true) {
        upstreamRequest.headers.set(HttpHeaders.refererHeader, ticket.referer!);
      }

      final upstreamResponse = await upstreamRequest.close();
      response.statusCode = upstreamResponse.statusCode;
      for (final header in const <String>{
        HttpHeaders.contentTypeHeader,
        HttpHeaders.contentLengthHeader,
        HttpHeaders.contentDisposition,
        HttpHeaders.acceptRangesHeader,
        HttpHeaders.contentRangeHeader,
        HttpHeaders.etagHeader,
        HttpHeaders.lastModifiedHeader,
        HttpHeaders.cacheControlHeader,
      }) {
        final values = upstreamResponse.headers[header];
        if (values == null) continue;
        for (final value in values) {
          response.headers.add(header, value);
        }
      }

      responseStarted = true;
      if (request.method == 'HEAD') {
        await response.close();
      } else {
        await upstreamResponse.pipe(response);
      }
    } catch (error, stackTrace) {
      GlobalProtectDebug.error('GP download relay request', error, stackTrace);
      if (!responseStarted) {
        response.statusCode = HttpStatus.badGateway;
      }
      try {
        await response.close();
      } catch (_) {}
    }
  }

  void _removeExpiredTickets() {
    final now = DateTime.now();
    _tickets.removeWhere((_, ticket) => now.difference(ticket.lastAccess) > _ticketTtl);
  }

  String _newToken() {
    final bytes = List<int>.generate(32, (_) => _random.nextInt(256), growable: false);
    return base64Url.encode(bytes).replaceAll('=', '');
  }

  Future<void> close() async {
    _tickets.clear();
    _startInFlight = null;
    final server = _server;
    _server = null;
    await server?.close(force: true);
  }
}

class _DownloadTicket {
  _DownloadTicket({required this.target, required this.cookieHeader, required this.userAgent, required this.referer})
    : lastAccess = DateTime.now();

  final Uri target;
  final String? cookieHeader;
  final String? userAgent;
  final String? referer;
  DateTime lastAccess;

  void touch() {
    lastAccess = DateTime.now();
  }
}
