import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:native_dio_adapter/native_dio_adapter.dart';
import 'package:native_dio_adapter_desktop/native_dio_adapter_desktop.dart';

/// Platform transport only: no cookies, redirects, or GP routing.
HttpClientAdapter createPlatformHttpClientAdapter() {
  if (Platform.isAndroid || Platform.isIOS) {
    return NativeAdapter(
      createCupertinoConfiguration: () =>
          URLSessionConfiguration.defaultSessionConfiguration()..httpShouldSetCookies = false,
    );
  }
  if (Platform.isWindows || Platform.isLinux) return NativeDesktopAdapter();
  return IOHttpClientAdapter();
}

/// Native TLS runs above the shared GP CONNECT proxy on Windows and Linux.
HttpClientAdapter createDesktopProxyAdapter(int port) => NativeDesktopAdapter(
  createWinHttpConfiguration: () =>
      WinHttpClientConfiguration(accessType: WinHttpAccessType.named, proxy: '127.0.0.1:$port'),
  createRhttpSettings: () => ClientSettings(proxySettings: ProxySettings.proxy('http://127.0.0.1:$port')),
);
