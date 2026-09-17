import 'dart:io';

import 'package:dio/dio.dart';

class RequestInterceptors extends InterceptorsWrapper {
  static const _initialReferer = "https://nportal.ntut.edu.tw";

  String referer = _initialReferer;

  void reset() => referer = _initialReferer;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (!options.headers.containsKey(HttpHeaders.refererHeader)) {
      options.headers[HttpHeaders.refererHeader] = referer;
    }
    referer = options.uri.toString();
    handler.next(options);
  }
}
