import 'dart:io';

import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import 'global_protect_debug.dart';
import 'global_protect_webview_proxy.dart';

/// Owns process-wide Android WebView proxy cleanup for GlobalProtect.
///
/// Cleanup is intentionally best-effort: logout must continue even if the
/// platform WebView implementation rejects ProxyOverride cleanup.
class GlobalProtectWebViewRuntime {
  const GlobalProtectWebViewRuntime._();

  static int _generation = 0;

  static int get generation => _generation;

  static bool isCurrent(int generation) => generation == _generation;

  static Future<void> reset() async {
    _generation++;
    if (Platform.isAndroid) {
      try {
        final supported = await WebViewFeature.isFeatureSupported(WebViewFeature.PROXY_OVERRIDE);
        if (supported) {
          await ProxyController.instance().clearProxyOverride();
          GlobalProtectDebug.log('WebView ProxyOverride cleared');
        }
      } catch (error, stackTrace) {
        GlobalProtectDebug.error('WebView ProxyOverride cleanup', error, stackTrace);
      }
    }

    try {
      await GlobalProtectWebViewProxyBridge.instance.close();
    } catch (error, stackTrace) {
      GlobalProtectDebug.error('WebView GP proxy bridge cleanup', error, stackTrace);
    }
  }
}
