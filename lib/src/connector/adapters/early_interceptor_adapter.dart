// 🎯 Dart imports:
import 'dart:async';
import 'dart:developer';
import 'dart:io';
import 'dart:typed_data';

// 📦 Package imports:
import 'package:dio/dio.dart';
import 'package:meta/meta.dart';

/// A function that may do somethings for the [originValues].
typedef HeaderDecorator = List<String> Function(List<String> originValues);

typedef HttpClientProvider = Future<HttpClient?> Function(RequestOptions options);

/// An adapter which lets you do something before the Dio interceptor executes.
/// Especially for changing the header of response.
///
/// Inherited from the `DefaultHttpClientAdapter` of Dio v4.0.6,
/// please refer to https://pub.dev/packages/dio for more details.
@immutable
@protected
@sealed
class EarlyInterceptorAdapter implements HttpClientAdapter {
  /// Initialize [EarlyInterceptorAdapter].
  ///
  /// [headerDecorators] is a [Map], each value of which is a Header modifier,
  /// and key is the target header name, suggest using the standard [HttpHeaders] library.
  /// Before outputting the final response, if a header provides a corresponding modifier,
  /// it will use the modifier to modify the header, so , the final output header value will be the modified version.
  factory EarlyInterceptorAdapter({
    Map<String, HeaderDecorator>? headerDecorators,
    HttpClient? httpClient,
    bool closeHttpClient = true,
    HttpClientProvider? httpClientProvider,
  }) => EarlyInterceptorAdapter._(
    headerDecorators: headerDecorators,
    httpClient: httpClient,
    closeHttpClient: closeHttpClient,
    httpClientProvider: httpClientProvider,
  );

  EarlyInterceptorAdapter._({
    this.headerDecorators,
    HttpClient? httpClient,
    this._closeHttpClient = true,
    this.httpClientProvider,
  })  : _defaultHttpClient = httpClient ?? HttpClient(),
        _usesInjectedHttpClient = httpClient != null;

  final HttpClient _defaultHttpClient;
  final bool _usesInjectedHttpClient;
  final bool _closeHttpClient;
  final Completer<void> _adapterLife = Completer<void>();
  final Map<String, HeaderDecorator>? headerDecorators;
  final HttpClientProvider? httpClientProvider;

  @override
  void close({bool force = false}) {
    if (!_adapterLife.isCompleted) {
      _adapterLife.complete();
    }
    if (_closeHttpClient) {
      _defaultHttpClient.close(force: force);
    }
  }

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (_adapterLife.isCompleted) {
      const msg = "Can't establish connection after [HttpClientAdapter] closed!";
      log(msg);
      throw Exception(msg);
    }

    final providedHttpClient = await httpClientProvider?.call(options);
    final httpClient = _configHttpClient(
      cancelFuture,
      options.connectTimeout,
      providedHttpClient: providedHttpClient,
    );
    final reqFuture = httpClient.openUrl(options.method, options.uri);

    Never throwConnectingTimeout() => throw DioException(
      requestOptions: options,
      error: 'Connecting timed out [${options.connectTimeout?.inMilliseconds ?? 0}ms]',
      type: DioExceptionType.connectionTimeout,
    );

    final HttpClientRequest request;
    try {
      final connectTimeout = options.connectTimeout;
      if (connectTimeout == null || connectTimeout == Duration.zero) {
        request = await reqFuture;
      } else {
        request = await reqFuture.timeout(connectTimeout);
      }

      options.headers.forEach((k, v) {
        if (v != null) request.headers.set(k, '$v');
      });
    } on SocketException catch (e) {
      if (e.message.contains('timed out')) {
        throwConnectingTimeout();
      }
      rethrow;
    } on TimeoutException {
      throwConnectingTimeout();
    }

    request
      ..followRedirects = options.followRedirects
      ..maxRedirects = options.maxRedirects;

    if (requestStream != null) {
      // Transform the request data
      var future = request.addStream(requestStream);
      final sendTimeout = options.sendTimeout;
      if (sendTimeout != null && sendTimeout != Duration.zero) {
        future = future.timeout(sendTimeout);
      }
      try {
        await future;
      } on TimeoutException {
        request.abort();
        throw DioException(
          requestOptions: options,
          error: 'Sending timeout[${sendTimeout?.inMilliseconds ?? 0}ms]',
          type: DioExceptionType.sendTimeout,
        );
      }
    }

    // [receiveTimeout] represents a timeout during data transfer! That is to say the
    // client has connected to the server.
    final receiveStart = DateTime.now().millisecondsSinceEpoch;

    var future = request.close();
    final receiveTimeout = options.receiveTimeout;
    if (receiveTimeout != null && receiveTimeout != Duration.zero) {
      future = future.timeout(receiveTimeout);
    }

    final HttpClientResponse responseStream;
    try {
      responseStream = await future;
    } on TimeoutException {
      throw DioException(
        requestOptions: options,
        error: 'Receiving data timeout[${receiveTimeout?.inMilliseconds ?? 0}ms]',
        type: DioExceptionType.receiveTimeout,
      );
    }

    final stream = responseStream.transform<Uint8List>(
      StreamTransformer.fromHandlers(
        handleData: (data, sink) {
          if (receiveTimeout != null &&
              receiveTimeout != Duration.zero &&
              DateTime.now().millisecondsSinceEpoch - receiveStart > receiveTimeout.inMilliseconds) {
            sink.addError(
              DioException(
                requestOptions: options,
                error: 'Receiving data timeout[${receiveTimeout.inMilliseconds}ms]',
                type: DioExceptionType.receiveTimeout,
              ),
            );
            responseStream.detachSocket().then((socket) => socket.destroy());
          } else {
            sink.add(Uint8List.fromList(data));
          }
        },
      ),
    );

    final headers = <String, List<String>>{};
    responseStream.headers.forEach((key, values) {
      final decorator = headerDecorators?[key];
      headers[key] = decorator != null ? decorator(values) : values;
    });

    return ResponseBody(
      stream,
      responseStream.statusCode,
      headers: headers,
      isRedirect: responseStream.isRedirect || responseStream.redirects.isNotEmpty,
      redirects: responseStream.redirects.map((e) => RedirectRecord(e.statusCode, e.method, e.location)).toList(),
      statusMessage: responseStream.reasonPhrase,
    );
  }

  HttpClient _configHttpClient(
    Future<void>? cancelFuture,
    Duration? connectionTimeout, {
    HttpClient? providedHttpClient,
  }) {
    final configuredConnectionTimeout = connectionTimeout == null || connectionTimeout == Duration.zero
        ? null
        : connectionTimeout;

    if (providedHttpClient != null) {
      providedHttpClient
        ..idleTimeout = const Duration(seconds: 3)
        ..connectionTimeout = configuredConnectionTimeout;
      return providedHttpClient;
    }

    if (cancelFuture != null && !_usesInjectedHttpClient) {
      final httpClient = HttpClient()
        ..userAgent = null
        ..idleTimeout = Duration.zero;

      cancelFuture.whenComplete(() {
        Future.delayed(Duration.zero).then((_) {
          try {
            httpClient.close(force: true);
          } catch (e) {
            log(e.toString());
          }
        });
      });
      return httpClient..connectionTimeout = configuredConnectionTimeout;
    }

    _defaultHttpClient
      ..idleTimeout = const Duration(seconds: 3)
      ..connectionTimeout = configuredConnectionTimeout;

    return _defaultHttpClient;
  }
}
