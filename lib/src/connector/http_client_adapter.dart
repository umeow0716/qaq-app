import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:native_dio_adapter/native_dio_adapter.dart';

/// Platform transport only: no cookies, redirects, or GP routing.
HttpClientAdapter createPlatformHttpClientAdapter() {
  if (Platform.isAndroid || Platform.isIOS) {
    return NativeAdapter(
      createCupertinoConfiguration: () =>
          URLSessionConfiguration.defaultSessionConfiguration()..httpShouldSetCookies = false,
    );
  }
  return IOHttpClientAdapter();
}
