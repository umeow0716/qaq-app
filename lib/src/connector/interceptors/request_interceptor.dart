import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:qaq_app/src/connector/core/dio_connector.dart';

class RequestInterceptors extends InterceptorsWrapper {
  static const _initialReferer = "https://nportal.ntut.edu.tw";
  static const _ntutClientIdentifier =
      'f39e5855ffb05dd0030e6cdd6b7b27f45303aa96dd5439f5021171b714afd755';

  String referer = _initialReferer;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (kDebugMode) {
      debugPrint(
        '[HTTP] request interceptors ready: ${options.method} '
        '${options.uri.host}${options.uri.path}',
      );
    }

    final host = options.uri.host.toLowerCase();
    if (DioConnector.nativePortalHosts.contains(host)) {
      options.headers.putIfAbsent('X-Client', () => _ntutClientIdentifier);
    }

    if (!options.headers.containsKey(HttpHeaders.refererHeader)) {
      options.headers[HttpHeaders.refererHeader] = referer;
    }
    options.headers.removeWhere(
      (_, value) => value == null || value.toString() == 'null',
    );
    if (kDebugMode) {
      print(
        '[HTTP] request interceptors headers: ${options.method} '
        '${options.uri.host}${options.uri.path}\n'
        '${options.headers}',
      );
      for(var entry in options.headers.entries) {
        print('[HTTP] request interceptors header: ${entry.key}=${entry.value}');
      }
    }
    referer = options.uri.toString();
    handler.next(options);
  }
}
