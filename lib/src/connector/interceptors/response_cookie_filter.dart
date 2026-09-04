import 'dart:io';

import 'package:dio/dio.dart';

/// Removes malformed/unwanted Set-Cookie values before CookieManager sees them.
class ResponseCookieFilter extends Interceptor {
  final List<RegExp> blockedCookieNamePatterns;

  ResponseCookieFilter({required this.blockedCookieNamePatterns});

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    final setCookieHeaders = response.headers[HttpHeaders.setCookieHeader];

    if (setCookieHeaders != null && setCookieHeaders.isNotEmpty) {
      final filteredHeaders = setCookieHeaders.where((header) {
        final separatorIndex = header.indexOf('=');
        final cookieName = (separatorIndex < 0 ? header : header.substring(0, separatorIndex)).trim();
        return !blockedCookieNamePatterns.any((pattern) => pattern.hasMatch(cookieName));
      }).toList(growable: false);

      response.headers.removeAll(HttpHeaders.setCookieHeader);
      for (final header in filteredHeaders) {
        response.headers.add(HttpHeaders.setCookieHeader, header);
      }
    }

    handler.next(response);
  }
}
