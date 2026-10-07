import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qaq_app/src/connector/adapters/host_routing_http_client_adapter.dart';

class _RecordingAdapter implements HttpClientAdapter {
  int fetchCount = 0;
  bool closed = false;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    fetchCount++;
    return ResponseBody.fromString('', 200);
  }

  @override
  void close({bool force = false}) {
    closed = true;
  }
}

void main() {
  test('routes configured hosts through the dedicated adapter', () async {
    final routed = _RecordingAdapter();
    final fallback = _RecordingAdapter();
    final adapter = HostRoutingHttpClientAdapter(
      routedHosts: const {'nportal.ntut.edu.tw'},
      routedAdapter: routed,
      defaultAdapter: fallback,
    );

    await adapter.fetch(RequestOptions(path: 'https://nportal.ntut.edu.tw/login.do'), null, null);

    expect(routed.fetchCount, 1);
    expect(fallback.fetchCount, 0);
  });

  test('keeps unrelated hosts on the default adapter', () async {
    final routed = _RecordingAdapter();
    final fallback = _RecordingAdapter();
    final adapter = HostRoutingHttpClientAdapter(
      routedHosts: const {'nportal.ntut.edu.tw'},
      routedAdapter: routed,
      defaultAdapter: fallback,
    );

    await adapter.fetch(RequestOptions(path: 'https://istudy.ntut.edu.tw/'), null, null);

    expect(routed.fetchCount, 0);
    expect(fallback.fetchCount, 1);
  });

  test('closes both delegates', () {
    final routed = _RecordingAdapter();
    final fallback = _RecordingAdapter();
    final adapter = HostRoutingHttpClientAdapter(
      routedHosts: const {'nportal.ntut.edu.tw'},
      routedAdapter: routed,
      defaultAdapter: fallback,
    );

    adapter.close(force: true);

    expect(routed.closed, isTrue);
    expect(fallback.closed, isTrue);
  });
}
