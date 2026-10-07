import 'dart:async';
import 'dart:io';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dart_big5/big5.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:native_dio_adapter/native_dio_adapter.dart';
import 'package:qaq_app/debug/log/log.dart';
import 'package:qaq_app/src/connector/adapters/early_interceptor_adapter.dart';
import 'package:qaq_app/src/connector/adapters/host_routing_http_client_adapter.dart';
import 'package:qaq_app/src/connector/global_protect/global_protect_app_session.dart';
import 'package:qaq_app/src/connector/global_protect/global_protect_debug.dart';
import 'package:qaq_app/src/connector/ischool_plus_access_guard.dart';
import 'package:qaq_app/src/connector/ntut_certificate_policy.dart';

import 'connector_parameter.dart';

typedef SavePathCallback = String Function(Headers responseHeaders);

class DioConnector {
  static const Duration _defaultRequestDeadline = Duration(seconds: 20);

  static final Map<String, String> _headers = {
    HttpHeaders.userAgentHeader: presetUserAgent,
    "Upgrade-Insecure-Requests": "1",
  };

  static final dioOptions = BaseOptions(
    connectTimeout: const Duration(seconds: 5),
    receiveTimeout: const Duration(seconds: 10),
    sendTimeout: const Duration(seconds: 5),
    headers: _headers,
    responseType: ResponseType.json,
    contentType: "application/x-www-form-urlencoded",
    validateStatus: (status) => status != null && status <= 500,
    responseDecoder: null,
  );

  static final headerDecorators = {
    // To force replace the strange header responded from the i-school APIs.
    // Please refer to https://github.com/NEO-TAT/tat_flutter/issues/63 for more details.
    HttpHeaders.contentTypeHeader: (List<String> headers) {
      headers.asMap().forEach((i, header) {
        if (header.contains('text/html;;')) {
          // Replace it to the standard header value.
          headers[i] = ContentType.html.toString();
        }
      });

      return headers;
    },
  };

  static const nativePortalHosts = <String>{
    'nportal.ntut.edu.tw',
    'app.ntut.edu.tw',
  };

  static Future<HttpClient?> _provideHttpClient(RequestOptions options) async {
    if (!IStudyAccessGuard.isIStudyUri(options.uri)) return null;

    final route = await IStudyAccessGuard.route();
    GlobalProtectDebug.log('Dio iStudy request route=${route.name}');
    switch (route) {
      case IStudyAccessRoute.direct:
        return null;
      case IStudyAccessRoute.blocked:
        throw const IStudyAccessBlockedException();
      case IStudyAccessRoute.vpn:
        GlobalProtectDebug.log('Dio requesting GP-backed HttpClient');
        return (await GlobalProtectAppSession.instance.ensureHttpClient()).client;
    }
  }

  static HttpClientAdapter _createHttpClientAdapter() {
    final nativeAdapter = NativeAdapter(
      createCupertinoConfiguration: () =>
          URLSessionConfiguration.defaultSessionConfiguration()
            ..httpShouldSetCookies = false,
    );

    if(Platform.isAndroid || Platform.isIOS) {
      return nativeAdapter;
    }

    return EarlyInterceptorAdapter(
      headerDecorators: headerDecorators,
      badCertificateCallback: NtutCertificatePolicy.allowBadCertificate,
      httpClientProvider: _provideHttpClient,
    );
  }

  final dio = Dio(dioOptions)..httpClientAdapter = _createHttpClientAdapter();

  CookieJar? _cookieJar;

  static final connectorError = Exception("Connector statusCode is not 200");

  DioConnector._privateConstructor();

  static final instance = DioConnector._privateConstructor();

  static String _big5Decoder(List<int> responseBytes, RequestOptions options, ResponseBody responseBody) =>
      big5.decode(responseBytes);

  Future<void> init({required List<Interceptor> interceptors, CookieJar? cookieJar}) async {
    if (cookieJar != null) {
      _cookieJar = cookieJar;
    }
    _requireCookieJar();

    // LocalStorage can reinitialize after logout. Rebuild the interceptor list
    // instead of stacking duplicate interceptors.
    dio.interceptors.clear();
    dio.interceptors.addAll(interceptors);
  }

  Future<void> deleteCookies() async {
    await _requireCookieJar().deleteAll();
  }

  Future<void> deleteCookiesFor(Uri uri) async {
    await _requireCookieJar().delete(uri, true);
  }

  CookieJar _requireCookieJar() {
    final cookieJar = _cookieJar;
    if (cookieJar == null) {
      throw StateError('DioConnector has not been initialized with a CookieJar.');
    }
    return cookieJar;
  }

  Future<String> getDataByPost(ConnectorParameter parameter) async {
    final response = await getDataByPostResponse(parameter);

    if (response.statusCode == HttpStatus.ok) {
      return response.toString().trim();
    }

    throw connectorError;
  }

  Future<String> getDataByGet(ConnectorParameter parameter) async {
    final response = await getDataByGetResponse(parameter);

    if (response.statusCode == HttpStatus.ok) {
      return response.toString().trim();
    }

    throw connectorError;
  }

  Future<Map<String, List<String>>> getHeadersByGet(ConnectorParameter parameter) async {
    final response = await _runWithDeadline<Response<ResponseBody>>(
      parameter,
      'GET',
      (cancelToken) => dio.get<ResponseBody>(
        parameter.url,
        options: _requestOptions(parameter, responseType: ResponseType.stream),
        cancelToken: cancelToken,
      ),
    );

    if (response.statusCode == HttpStatus.ok) {
      return response.headers.map;
    }

    throw connectorError;
  }

  Future<Response> getDataByGetResponse(ConnectorParameter parameter) {
    return _runWithDeadline<Response<dynamic>>(
      parameter,
      'GET',
      (cancelToken) => dio.get(
        parameter.url,
        queryParameters: parameter.data,
        options: _requestOptions(parameter),
        cancelToken: cancelToken,
      ),
    );
  }

  Future<Response<List<int>>> getBytesByGetResponse(ConnectorParameter parameter) {
    return _runWithDeadline<Response<List<int>>>(
      parameter,
      'GET',
      (cancelToken) => dio.get<List<int>>(
        parameter.url,
        queryParameters: parameter.data,
        options: _requestOptions(parameter, responseType: ResponseType.bytes),
        cancelToken: cancelToken,
      ),
    );
  }

  Future<Response> getDataByPostResponse(ConnectorParameter parameter) {
    return _runWithDeadline<Response<dynamic>>(
      parameter,
      'POST',
      (cancelToken) => dio.post(
        parameter.url,
        data: parameter.data,
        options: _requestOptions(parameter),
        cancelToken: cancelToken,
      ),
    );
  }

  Future<T> _runWithDeadline<T>(
    ConnectorParameter parameter,
    String method,
    Future<T> Function(CancelToken cancelToken) request,
  ) async {
    final cancelToken = CancelToken();
    final deadline = _requestDeadline(parameter);
    final target = _safeRequestTarget(parameter.url);
    final stopwatch = Stopwatch()..start();

    if (kDebugMode) {
      debugPrint('[HTTP] $method $target start (deadline=${deadline.inSeconds}s)');
    }

    try {
      final result = await request(cancelToken).timeout(
        deadline,
        onTimeout: () {
          final error = TimeoutException(
            '$method $target did not complete within ${deadline.inSeconds}s',
            deadline,
          );
          if (!cancelToken.isCancelled) {
            cancelToken.cancel(error);
          }
          throw error;
        },
      );

      if (kDebugMode) {
        debugPrint('[HTTP] $method $target completed in ${stopwatch.elapsedMilliseconds}ms');
      }
      return result;
    } catch (error, stackTrace) {
      if (kDebugMode) {
        debugPrint(
          '[HTTP] $method $target failed after ${stopwatch.elapsedMilliseconds}ms: $error',
        );
        debugPrintStack(stackTrace: stackTrace);
      }
      rethrow;
    } finally {
      stopwatch.stop();
    }
  }

  Duration _requestDeadline(ConnectorParameter parameter) {
    final timeout = parameter.timeout;
    if (timeout == null || timeout <= Duration.zero) {
      return _defaultRequestDeadline;
    }

    // ConnectorParameter.timeout is also used for each individual Dio network
    // phase. Give the whole request a small margin for interceptors and body
    // decoding while still guaranteeing that the Future always settles.
    return timeout + const Duration(seconds: 5);
  }

  String _safeRequestTarget(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.host.isEmpty) return '<invalid-url>';

    final port = uri.hasPort ? ':${uri.port}' : '';
    return '${uri.scheme}://${uri.host}$port${uri.path}';
  }

  Options _requestOptions(ConnectorParameter parameter, {ResponseType? responseType}) {
    final headers = <String, dynamic>{HttpHeaders.userAgentHeader: parameter.userAgent};
    final referer = parameter.referer;
    if (referer != null) {
      headers[HttpHeaders.refererHeader] = referer;
    }

    final timeout = parameter.timeout;
    return Options(
      headers: headers,
      contentType: parameter.contentType,
      responseType: responseType,
      connectTimeout: timeout,
      receiveTimeout: timeout,
      sendTimeout: timeout,
      responseDecoder: parameter.charsetName == 'big5' ? _big5Decoder : null,
    );
  }

  Future<void> download(
    String url,
    SavePathCallback savePath, {
    required ProgressCallback progressCallback,
    required CancelToken cancelToken,
    required Map<String, dynamic> header,
  }) async {
    await dio
        .downloadUri(
          Uri.parse(url),
          savePath,
          onReceiveProgress: progressCallback,
          cancelToken: cancelToken,
          options: Options(receiveTimeout: Duration.zero, headers: header),
        )
        .catchError((onError, stack) {
          Log.eWithStack(onError.toString(), stack);
          throw onError;
        });
  }

  Map<String, String> get headers => _headers;

  CookieJar get cookiesManager => _requireCookieJar();
}
