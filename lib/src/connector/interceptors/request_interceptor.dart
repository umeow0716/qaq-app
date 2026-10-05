import 'dart:io';

import 'package:dio/dio.dart';
import 'package:qaq_app/src/connector/windows_certificate_warmup.dart';

class RequestInterceptors extends InterceptorsWrapper {
  static const _initialReferer = "https://nportal.ntut.edu.tw";

  String referer = _initialReferer;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    _forwardAfterWarmup(options, handler);
  }

  Future<void> _forwardAfterWarmup(RequestOptions options, RequestInterceptorHandler handler) async {
    if (options.uri.host == WindowsCertificateWarmup.portalHost) {
      await WindowsCertificateWarmup.ensure();
    }

    if (!options.headers.containsKey(HttpHeaders.refererHeader)) {
      options.headers[HttpHeaders.refererHeader] = referer;
    }
    referer = options.uri.toString();
    handler.next(options);
  }
}
