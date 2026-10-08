import 'dart:io';

import 'global_protect_debug.dart';
import 'global_protect_routing.dart';
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
  static Future<void>? _enableInFlight;

  /// Windows fixes proxy settings when its first WebView environment is made.
  /// Bind early without opening the VPN; enable routing only for a study flow.
  static Future<void> prepareWindowsEnvironment() async {
    if (!Platform.isWindows || GlobalProtectWebViewProxyController.isWindowsEnvironmentPrepared) return;
    final currentGeneration = generation;
    final port = await GlobalProtectWebViewProxyBridge.instance.ensureListening(
      vpnHosts: GlobalProtectRouting.webViewProxyHosts,
    );
    if (!isCurrent(currentGeneration)) throw StateError('WebView proxy preparation was reset.');
    await GlobalProtectWebViewProxyController.setProxyOverride(
      port: port,
      hosts: GlobalProtectRouting.webViewProxyHosts,
    );
    if (!isCurrent(currentGeneration)) {
      await reset();
      throw StateError('WebView proxy preparation was reset.');
    }
  }

  /// One setup path for all supported WebViews; concurrent navigations share it.
  static Future<void> enable() {
    final existing = _enableInFlight;
    if (existing != null) return existing;
    final future = _enable();
    _enableInFlight = future;
    return future.whenComplete(() {
      if (identical(_enableInFlight, future)) _enableInFlight = null;
    });
  }

  static Future<void> _enable() async {
    if (!Platform.isAndroid && !Platform.isWindows && !Platform.isLinux) {
      throw UnsupportedError('GlobalProtect WebView proxy supports Android, Windows and Linux.');
    }
    final currentGeneration = generation;
    if (Platform.isWindows) {
      await prepareWindowsEnvironment();
      await GlobalProtectWebViewProxyBridge.instance.enableVpnRouting();
    } else {
      final port = await GlobalProtectWebViewProxyBridge.instance.ensureStarted(
        vpnHosts: GlobalProtectRouting.webViewProxyHosts,
      );
      if (!isCurrent(currentGeneration)) throw StateError('WebView proxy setup was reset.');
      await GlobalProtectWebViewProxyController.setProxyOverride(
        port: port,
        hosts: GlobalProtectRouting.webViewProxyHosts,
      );
    }
    if (!isCurrent(currentGeneration)) {
      await reset();
      throw StateError('WebView proxy setup was reset.');
    }
  }

  static int get generation => _generation;

  static bool isCurrent(int generation) => generation == _generation;

  static Future<void> reset() async {
    _generation++;
    _enableInFlight = null;
    GlobalProtectWebViewProxyBridge.instance.disableVpnRouting();
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
