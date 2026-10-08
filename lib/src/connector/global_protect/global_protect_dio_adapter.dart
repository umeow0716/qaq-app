import 'dart:typed_data';

import 'package:dio/dio.dart';

import 'global_protect_routing.dart';

typedef StudyRouteResolver = Future<IStudyAccessRoute> Function();
typedef TunnelAdapterProvider = Future<HttpClientAdapter> Function();

/// Selects the transport for each request, including every redirect hop.
/// The app session owns GP clients; this adapter owns only the direct adapter.
class GlobalProtectDioAdapter implements HttpClientAdapter {
  GlobalProtectDioAdapter({
    required this.directAdapter,
    required this.resolveRoute,
    TunnelAdapterProvider? tunnelAdapter,
  }) : _tunnelAdapter = tunnelAdapter ?? (() async => throw StateError('No GP tunnel client was configured.'));

  final HttpClientAdapter directAdapter;
  final StudyRouteResolver resolveRoute;
  final TunnelAdapterProvider _tunnelAdapter;
  bool _closed = false;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    _checkActive(options);
    final data = options.data;
    final redirectUri = data is Map ? data['redirect_uri'] : null;
    final needsTunnel = GlobalProtectRouting.requiresStudyRoute(
      options.uri,
      ssoRedirectUri: redirectUri is String ? redirectUri : null,
    );
    if (!needsTunnel) return directAdapter.fetch(options, requestStream, cancelFuture);

    final route = await resolveRoute();
    _checkActive(options);
    switch (route) {
      case IStudyAccessRoute.direct:
        return directAdapter.fetch(options, requestStream, cancelFuture);
      case IStudyAccessRoute.blocked:
        throw const IStudyAccessBlockedException();
      case IStudyAccessRoute.vpn:
        // Portal sessions are bound to the login connection's source route.
        // Keep the OAuth exchange direct; the redirect to iStudy selects GP.
        if (GlobalProtectRouting.normalizeHost(options.uri.host) == GlobalProtectRouting.portalHost) {
          return directAdapter.fetch(options, requestStream, cancelFuture);
        }
        final client = await _tunnelAdapter();
        _checkActive(options);
        // Resolve afresh so a reconnect never reuses the previous session client.
        return client.fetch(options, requestStream, cancelFuture);
    }
  }

  void _checkActive(RequestOptions options) {
    if (_closed) throw StateError('HTTP adapter is closed.');
    final cancelled = options.cancelToken?.cancelError;
    if (cancelled != null) throw cancelled;
  }

  @override
  void close({bool force = false}) {
    if (_closed) return;
    _closed = true;
    directAdapter.close(force: force);
  }
}
