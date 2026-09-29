import 'package:webview_flutter_android/webview_flutter_android.dart';
// webview_flutter_android does not expose DownloadListener metadata publicly.
// Pinning 4.14.1 keeps this isolated bridge stable until the upstream API does.
// ignore: implementation_imports
import 'package:webview_flutter_android/src/android_webkit.g.dart' as android_webview;
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';

typedef QAQWebViewDownloadCallback = void Function(
  String url,
  String userAgent,
  String contentDisposition,
  String mimeType,
  int contentLength,
);

class QAQAndroidNavigationDelegate extends AndroidNavigationDelegate {
  QAQAndroidNavigationDelegate({required QAQWebViewDownloadCallback onDownloadStart})
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
