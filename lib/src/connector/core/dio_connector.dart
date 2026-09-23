import 'dart:io';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dart_big5/big5.dart';
import 'package:dio/dio.dart';
import 'package:qaq_app/debug/log/log.dart';
import 'package:qaq_app/src/connector/adapters/early_interceptor_adapter.dart';
import 'package:qaq_app/src/connector/global_protect/global_protect_app_session.dart';
import 'package:qaq_app/src/connector/global_protect/global_protect_debug.dart';
import 'package:qaq_app/src/connector/ischool_plus_access_guard.dart';

import 'connector_parameter.dart';

typedef SavePathCallback = String Function(Headers responseHeaders);

class DioConnector {
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

  final dio = Dio(dioOptions)
    ..httpClientAdapter = EarlyInterceptorAdapter(
      headerDecorators: headerDecorators,
      httpClientProvider: (options) async {
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
      },
    );

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
    final response = await dio.get<ResponseBody>(
      parameter.url,
      options: _requestOptions(parameter, responseType: ResponseType.stream),
    );

    if (response.statusCode == HttpStatus.ok) {
      return response.headers.map;
    }

    throw connectorError;
  }

  Future<Response> getDataByGetResponse(ConnectorParameter parameter) async {
    final url = parameter.url;
    final data = parameter.data;
    return await dio.get(url, queryParameters: data, options: _requestOptions(parameter));
  }

  Future<Response<List<int>>> getBytesByGetResponse(ConnectorParameter parameter) async {
    return await dio.get<List<int>>(
      parameter.url,
      queryParameters: parameter.data,
      options: _requestOptions(parameter, responseType: ResponseType.bytes),
    );
  }

  Future<Response> getDataByPostResponse(ConnectorParameter parameter) async {
    final url = parameter.url;
    return await dio.post(url, data: parameter.data, options: _requestOptions(parameter));
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
