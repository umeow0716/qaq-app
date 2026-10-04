import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:qaq_app/ui/pages/webview/qaq_web_view_desktop.dart';
import 'package:qaq_app/ui/pages/webview/qaq_web_view_mobile.dart';

class QAQWebView extends StatelessWidget {
  const QAQWebView({
    super.key,
    required this.initialUrl,
    this.title,
    this.showAppBar = true,
    this.onDesktopClose,
  });

  final Uri initialUrl;
  final String? title;
  final bool showAppBar;
  final VoidCallback? onDesktopClose;

  @override
  Widget build(BuildContext context) {
    if (Platform.isAndroid || Platform.isIOS) {
      return QAQWebViewMobile(initialUrl: initialUrl, title: title);
    }

    if (Platform.isLinux || Platform.isWindows) {
      return QAQWebViewDesktop(
        initialUrl: initialUrl,
        title: title,
        showAppBar: showAppBar,
        onClose: onDesktopClose,
      );
    }

    throw UnsupportedError('QAQWebView is not supported on ${Platform.operatingSystem}.');
  }
}
