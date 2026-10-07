import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter/foundation.dart';
import 'package:meta/meta.dart';

/// A function that may modify raw response header values before Dio transforms
/// the response body.
typedef HeaderDecorator = List<String> Function(List<String> originValues);

typedef HttpClientProvider = Future<HttpClient?> Function(RequestOptions options);

typedef BadCertificateCallback = bool Function(
  X509Certificate certificate,
  String host,
  int port,
);

HttpClient _newHttpClient(BadCertificateCallback? badCertificateCallback) {
  return HttpClient()
    ..idleTimeout = const Duration(seconds: 3)
    ..badCertificateCallback = badCertificateCallback;
}

/// Applies QAQ's pre-transform response header fixes while delegating all
/// socket, timeout, cancellation, redirect and stream handling to Dio's current
/// [IOHttpClientAdapter].
///
/// The previous implementation was copied from Dio 4.0.6 and had gradually
/// diverged from Dio 5.x networking semantics. Keeping this adapter as a thin
/// wrapper avoids maintaining a second HTTP stack while preserving the two QAQ
/// hooks that are still required:
///
/// * choosing the GlobalProtect-backed [HttpClient] per request;
/// * normalizing malformed response headers before Dio decodes the body.
@immutable
@protected
@sealed
class EarlyInterceptorAdapter implements HttpClientAdapter {
  factory EarlyInterceptorAdapter({
    Map<String, HeaderDecorator>? headerDecorators,
    HttpClient? httpClient,
    bool closeHttpClient = true,
    HttpClientProvider? httpClientProvider,
    BadCertificateCallback? badCertificateCallback,
  }) => EarlyInterceptorAdapter._(
    headerDecorators: headerDecorators,
    httpClient: httpClient,
    closeHttpClient: closeHttpClient,
    httpClientProvider: httpClientProvider,
    badCertificateCallback: badCertificateCallback,
  );

  EarlyInterceptorAdapter._({
    this.headerDecorators,
    HttpClient? httpClient,
    required bool closeHttpClient,
    this.httpClientProvider,
    BadCertificateCallback? badCertificateCallback,
  }) : _closeHttpClient = closeHttpClient,
       _defaultAdapter = IOHttpClientAdapter(
         createHttpClient: () =>
             httpClient ?? _newHttpClient(badCertificateCallback),
       );

  final Map<String, HeaderDecorator>? headerDecorators;
  final HttpClientProvider? httpClientProvider;
  final bool _closeHttpClient;
  final IOHttpClientAdapter _defaultAdapter;

  bool _closed = false;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (_closed) {
      throw StateError(
        "Can't establish connection after [HttpClientAdapter] closed!",
      );
    }

    if (kDebugMode) {
      debugPrint(
        '[HTTP] adapter fetch: ${options.method} '
        '${options.uri.host}${options.uri.path}',
      );
    }

    final providedHttpClient = await httpClientProvider?.call(options);
    final IOHttpClientAdapter adapter;
    if (providedHttpClient == null) {
      adapter = _defaultAdapter;
    } else {
      // The GP session owns this client. Do not close it when this one request
      // completes; IOHttpClientAdapter still applies the request's connection
      // timeout and cancellation semantics to the request itself.
      providedHttpClient.idleTimeout = const Duration(seconds: 3);
      adapter = IOHttpClientAdapter(
        createHttpClient: () => providedHttpClient,
      );
    }

    final response = await adapter.fetch(options, requestStream, cancelFuture);
    if (kDebugMode) {
      debugPrint(
        '[HTTP] adapter response headers: ${options.method} '
        '${options.uri.host}${options.uri.path} status=${response.statusCode}',
      );
    }
    _decorateHeaders(response);
    return response;
  }

  void _decorateHeaders(ResponseBody response) {
    final decorators = headerDecorators;
    if (decorators == null || decorators.isEmpty) return;

    for (final entry in response.headers.entries.toList(growable: false)) {
      final decorator = decorators[entry.key.toLowerCase()];
      if (decorator == null) continue;
      response.headers[entry.key] = decorator(
        List<String>.from(entry.value),
      );
    }
  }

  @override
  void close({bool force = false}) {
    if (_closed) return;
    _closed = true;
    if (_closeHttpClient) {
      _defaultAdapter.close(force: force);
    }
  }
}
