import 'dart:async';
import 'dart:io';

import 'package:qaq_app/src/connector/web_view_file_transfer.dart';
import 'package:qaq_app/ui/pages/webview/platform/android_download_navigation_delegate.dart';
import 'package:webview_all/webview_all.dart';
import 'package:webview_all_android/webview_all_android.dart';

typedef QAQWebViewDownloadHandler = Future<void> Function({
  required String url,
  required String userAgent,
  required String contentDisposition,
  required String mimeType,
  required int contentLength,
});

/// Holds the platform-specific WebView setup in one place.
///
/// Shared WebView code should stay platform-neutral. Android keeps the custom
/// DownloadListener and file picker bridge; desktop is intentionally left to
/// webview_all's native Linux/Windows behavior for this first adaptation pass.
class QAQWebViewPlatformAdapter {
  const QAQWebViewPlatformAdapter._();

  static NavigationDelegate createNavigationDelegate({
    required void Function(int progress) onProgress,
    required FutureOr<NavigationDecision> Function(NavigationRequest request) onNavigationRequest,
    required void Function(String url) onPageStarted,
    required void Function(String url) onPageFinished,
    required QAQWebViewDownloadHandler onDownloadStart,
  }) {
    if (Platform.isAndroid) {
      return NavigationDelegate.fromPlatform(
        AndroidDownloadNavigationDelegate(
          onDownloadStart: (url, userAgent, contentDisposition, mimeType, contentLength) {
            unawaited(
              onDownloadStart(
                url: url,
                userAgent: userAgent,
                contentDisposition: contentDisposition,
                mimeType: mimeType,
                contentLength: contentLength,
              ),
            );
          },
        ),
        onProgress: onProgress,
        onNavigationRequest: onNavigationRequest,
        onPageStarted: onPageStarted,
        onPageFinished: onPageFinished,
      );
    }

    return NavigationDelegate(
      onProgress: onProgress,
      onNavigationRequest: onNavigationRequest,
      onPageStarted: onPageStarted,
      onPageFinished: onPageFinished,
    );
  }

  static Future<void> configureFilePicker(WebViewController controller) async {
    if (!Platform.isAndroid) return;
    final platformController = controller.platform;
    if (platformController is! AndroidWebViewController) return;

    await platformController.setOnShowFileSelector(
      (params) => WebViewFileTransfer.pickSystemFiles(
        acceptTypes: params.acceptTypes,
        mode: params.mode.name,
        capture: params.isCaptureEnabled,
        filenameHint: params.filenameHint,
      ),
    );
  }
}
