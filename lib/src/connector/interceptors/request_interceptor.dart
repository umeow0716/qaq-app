import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio_redirect_interceptor/dio_redirect_interceptor.dart';
import 'package:flutter/foundation.dart';

class RequestInterceptors extends Interceptor {
  static const _portalHosts = {'nportal.ntut.edu.tw', 'app.ntut.edu.tw'};
  static const _ntutClientIdentifier = 'f39e5855ffb05dd0030e6cdd6b7b27f45303aa96dd5439f5021171b714afd755';

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (_portalHosts.contains(options.uri.host.toLowerCase())) {
      options.headers.putIfAbsent('X-Client', () => _ntutClientIdentifier);
    }
    // Per-request state avoids concurrent requests borrowing one another's URL.
    options.headers.putIfAbsent(
      HttpHeaders.refererHeader,
      () => options.redirectContext?.previousUri.toString() ?? 'https://nportal.ntut.edu.tw/',
    );
    // CookieManager sets Cookie:null when the jar is empty; native adapters
    // otherwise send it literally and the campus gateway rejects the request.
    options.headers = {
      for (final entry in options.headers.entries)
        if (entry.value != null && entry.value.toString() != 'null') entry.key: entry.value,
    };
    if (kDebugMode) {
      debugPrint('[HTTP] ${options.method} ${options.uri.host}${options.uri.path}');
    }
    handler.next(options);
  }
}
