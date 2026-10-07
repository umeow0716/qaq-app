import 'dart:typed_data';

import 'package:dio/dio.dart';

/// Routes selected hosts through a dedicated Dio HTTP adapter while preserving
/// the existing adapter for every other request.
class HostRoutingHttpClientAdapter implements HttpClientAdapter {
  HostRoutingHttpClientAdapter({
    required Set<String> routedHosts,
    required HttpClientAdapter routedAdapter,
    required HttpClientAdapter defaultAdapter,
  }) : _routedHosts = routedHosts.map((host) => host.toLowerCase()).toSet(),
       _routedAdapter = routedAdapter,
       _defaultAdapter = defaultAdapter;

  final Set<String> _routedHosts;
  final HttpClientAdapter _routedAdapter;
  final HttpClientAdapter _defaultAdapter;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    final host = options.uri.host.toLowerCase();
    final adapter = _routedHosts.contains(host) ? _routedAdapter : _defaultAdapter;
    return adapter.fetch(options, requestStream, cancelFuture);
  }

  @override
  void close({bool force = false}) {
    _routedAdapter.close(force: force);
    _defaultAdapter.close(force: force);
  }
}
