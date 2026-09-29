// ignore: depend_on_referenced_packages
import 'package:webview_all_android/webview_all_android.dart';
// webview_all_android does not expose DownloadListener metadata publicly.
// Keep this isolated bridge small so desktop migration can use webview_all
// without spreading Android internals across the shared WebView page.
// ignore: depend_on_referenced_packages, implementation_imports
import 'package:webview_all_android/src/android_webkit.g.dart' as android_webview;
// ignore: depend_on_referenced_packages
import 'package:webview_platform_interface/webview_platform_interface.dart';

typedef QAQWebViewDownloadCallback = void Function(
  String url,
  String userAgent,
  String contentDisposition,
  String mimeType,
  int contentLength,
);

class AndroidDownloadNavigationDelegate extends AndroidNavigationDelegate {
  AndroidDownloadNavigationDelegate({required QAQWebViewDownloadCallback onDownloadStart})
    : _qaqDownloadListener = android_webview.DownloadListener(
        onDownloadStart: (_, url, userAgent, contentDisposition, mimeType, contentLength) {
          onDownloadStart(url, userAgent, contentDisposition, mimeType, contentLength);
        },
      ),
      super(const PlatformNavigationDelegateCreationParams());

  final android_webview.DownloadListener _qaqDownloadListener;

  @override
  android_webview.DownloadListener get androidDownloadListener => _qaqDownloadListener;
}
