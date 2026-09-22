import 'dart:io';

import 'package:flutter/services.dart';
import 'package:qaq_app/src/config/app_config.dart';

/// Native Android bridge for the process-wide WebView ProxyOverride.
///
/// The GlobalProtect HTTP proxy itself remains implemented in Dart. This class
/// only applies or clears AndroidX WebKit's process-wide proxy configuration.
class GlobalProtectWebViewProxyController {
  const GlobalProtectWebViewProxyController._();

  static const MethodChannel _channel = MethodChannel(AppConfig.methodChannelName);

  /// Applies the loopback proxy and returns whether reverse-bypass allow-list
  /// mode is supported by the installed Android WebView.
  static Future<bool> setProxyOverride({required int port, required String host}) async {
    if (!Platform.isAndroid) {
      throw UnsupportedError('The experimental iStudy WebView VPN bridge currently supports Android only.');
    }

    final reverseBypassSupported = await _channel.invokeMethod<bool>('set_webview_proxy_override', <String, Object>{
      'port': port,
      'host': host,
    });
    if (reverseBypassSupported == null) {
      throw StateError('Android did not report the WebView proxy mode.');
    }
    return reverseBypassSupported;
  }

  static Future<void> clearProxyOverride() async {
    if (!Platform.isAndroid) return;
    await _channel.invokeMethod<void>('clear_webview_proxy_override');
  }
}
