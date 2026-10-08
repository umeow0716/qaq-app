import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:native_dio_adapter/native_dio_adapter.dart';
import 'package:native_dio_adapter_desktop/native_dio_adapter_desktop.dart';
// The pinned adapter exposes TlsSettings but does not re-export TlsVersion.
// ignore: implementation_imports
import 'package:native_dio_adapter_desktop/src/rhttp/src/model/settings.dart' show TlsVersion;

// NTUT resets rustls's default TLS 1.2/1.3 ClientHello. TLS 1.3-only
// succeeds while retaining certificate verification and modern encryption.
const _linuxTlsSettings = TlsSettings(minTlsVersion: TlsVersion.tls13, maxTlsVersion: TlsVersion.tls13);
const _linuxVpnTlsSettings = TlsSettings(minTlsVersion: TlsVersion.tls12, maxTlsVersion: TlsVersion.tls12);

ClientSettings _linuxClientSettings({ProxySettings? proxySettings}) =>
    ClientSettings(tlsSettings: _linuxTlsSettings, proxySettings: proxySettings);

/// Platform transport only: no cookies, redirects, or GP routing.
/// GlobalProtect control servers use TLS 1.2-only on Linux; other requests
/// use TLS 1.3-only to avoid NTUT's resets of mixed-version ClientHello.
HttpClientAdapter createPlatformHttpClientAdapter({bool linuxTls12Only = false}) {
  if (Platform.isAndroid || Platform.isIOS) {
    return NativeAdapter(
      createCupertinoConfiguration: () =>
          URLSessionConfiguration.defaultSessionConfiguration()..httpShouldSetCookies = false,
    );
  }
  if (Platform.isWindows || Platform.isLinux) {
    return NativeDesktopAdapter(
      createRhttpSettings: () =>
          linuxTls12Only ? const ClientSettings(tlsSettings: _linuxVpnTlsSettings) : _linuxClientSettings(),
    );
  }
  return IOHttpClientAdapter();
}

/// Native TLS runs above the shared GP CONNECT proxy on Windows and Linux.
HttpClientAdapter createDesktopProxyAdapter(int port) => NativeDesktopAdapter(
  createWinHttpConfiguration: () =>
      WinHttpClientConfiguration(accessType: WinHttpAccessType.named, proxy: '127.0.0.1:$port'),
  createRhttpSettings: () => _linuxClientSettings(proxySettings: ProxySettings.proxy('http://127.0.0.1:$port')),
);
