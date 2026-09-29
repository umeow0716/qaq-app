import 'global_protect_debug.dart';
import 'global_protect_webview_proxy.dart';
import 'global_protect_webview_proxy_controller.dart';

/// Owns process-wide WebView proxy cleanup for GlobalProtect.
///
/// Cleanup is intentionally best-effort: logout must continue even if the
/// platform WebView implementation rejects proxy cleanup. Windows WebView2
/// proxy arguments are process-scoped, so its loopback bridge stays alive.
class GlobalProtectWebViewRuntime {
  const GlobalProtectWebViewRuntime._();

  static int _generation = 0;

  static int get generation => _generation;

  static bool isCurrent(int generation) => generation == _generation;

  static Future<void> reset() async {
    _generation++;
    var closeLoopbackBridge = true;
    try {
      closeLoopbackBridge = await GlobalProtectWebViewProxyController.clearProxyOverride();
      GlobalProtectDebug.log('WebView ProxyOverride cleanup closeBridge=$closeLoopbackBridge');
    } catch (error, stackTrace) {
      GlobalProtectDebug.error('WebView ProxyOverride cleanup', error, stackTrace);
    }

    if (!closeLoopbackBridge) {
      GlobalProtectDebug.log('leaving WebView GP proxy bridge alive for sticky desktop WebView environment');
      return;
    }

    try {
      await GlobalProtectWebViewProxyBridge.instance.close();
    } catch (error, stackTrace) {
      GlobalProtectDebug.error('WebView GP proxy bridge cleanup', error, stackTrace);
    }
  }
}
