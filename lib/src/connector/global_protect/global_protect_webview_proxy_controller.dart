import 'dart:io';

import 'package:flutter/services.dart';
import 'package:qaq_app/src/config/app_config.dart';
import 'package:qaq_app/src/connector/global_protect/global_protect_debug.dart';
import 'package:qaq_app/src/connector/global_protect/global_protect_webview_proxy.dart';
import 'package:webview_all/webview_all.dart';
// ignore: depend_on_referenced_packages
import 'package:webview_all_windows/webview_all_windows.dart';

/// Native WebView proxy bridge configuration.
///
/// Android can apply and clear ProxyOverride at runtime. Windows WebView2 can
/// only receive proxy settings through its shared environment before the first
/// WebView controller is created, so that configuration is intentionally sticky
/// for this process. Windows uses a PAC served by the loopback bridge so only
/// the configured iStudy host enters that proxy; normal sites stay on WebView2's
/// native DIRECT path. The bridge can remain bound while VPN routing is disabled
/// and starts using GlobalProtect only after the access guard selects it. Linux
/// uses webview_all's PlatformProxyController implementation backed by WebKitGTK
/// network proxy settings.
class GlobalProtectWebViewProxyController {
  const GlobalProtectWebViewProxyController._();

  static const MethodChannel _channel = MethodChannel(AppConfig.methodChannelName);
  static String? _windowsAdditionalArguments;

  /// Applies the loopback proxy and returns whether Android reverse-bypass
  /// allow-list mode is supported.
  static Future<bool> setProxyOverride({required int port, required String host}) async {
    if (Platform.isAndroid) {
      final reverseBypassSupported = await _channel.invokeMethod<bool>('set_webview_proxy_override', <String, Object>{
        'port': port,
        'host': host,
      });
      if (reverseBypassSupported == null) {
        throw StateError('Android did not report the WebView proxy mode.');
      }
      return reverseBypassSupported;
    }

    if (Platform.isWindows) {
      final arguments = _windowsProxyArguments(port: port, host: host);
      await WindowsWebViewController.ensureEnvironment(additionalArguments: arguments);
      _windowsAdditionalArguments = arguments;
      GlobalProtectDebug.log('Windows WebView2 proxy environment active args=$arguments');
      return false;
    }

    if (Platform.isLinux) {
      final proxyUrl = _loopbackProxyUrl(port: port);
      await ProxyController.instance().setProxyOverride(
        settings: ProxySettings(
          bypassRules: _desktopProxyBypassRules,
          proxyRules: <ProxyRule>[
            ProxyRule(url: proxyUrl),
          ],
        ),
      );
      GlobalProtectDebug.log('Linux WebKitGTK proxy active url=$proxyUrl');
      return false;
    }

    throw UnsupportedError('The experimental iStudy WebView VPN bridge currently supports Android, Windows, and Linux only.');
  }

  /// Attempts to clear native WebView proxy configuration.
  ///
  /// Returns whether the Dart loopback bridge may also be closed. Windows keeps
  /// its WebView2 environment for the lifetime of this process, so the bridge
  /// must remain alive after best-effort cleanup.
  static Future<bool> clearProxyOverride() async {
    if (Platform.isAndroid) {
      await _channel.invokeMethod<void>('clear_webview_proxy_override');
      return true;
    }

    if (Platform.isWindows) {
      if (_windowsAdditionalArguments != null) {
        GlobalProtectDebug.log(
          'Windows WebView2 proxy environment is process-scoped; keeping loopback bridge alive until app exit.',
        );
      }
      return false;
    }

    if (Platform.isLinux) {
      await ProxyController.instance().clearProxyOverride();
      GlobalProtectDebug.log('Linux WebKitGTK proxy cleared');
      return true;
    }

    return true;
  }

  static const List<String> _desktopProxyBypassRules = <String>[
    'localhost',
    '127.0.0.1',
    '::1',
  ];

  static String _loopbackProxyUrl({required int port}) => 'http://127.0.0.1:$port';

  static String _windowsProxyArguments({required int port, required String host}) {
    if (host.isEmpty) throw ArgumentError.value(host, 'host', 'Proxy target host must not be empty.');

    // Keep normal sites on WebView2's native network stack. The PAC is served
    // by the already-bound QAQ loopback listener and returns PROXY only for the
    // iStudy host; every other destination is DIRECT. This avoids forcing sites
    // such as Google through the Dart CONNECT tunnel while keeping the immutable
    // WebView2 environment ready for a later iStudy VPN redirect.
    return '--proxy-pac-url=http://127.0.0.1:$port${GlobalProtectWebViewProxyBridge.windowsPacPath}';
  }
}
