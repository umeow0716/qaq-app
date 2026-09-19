import 'package:qaq_app/src/r.dart';
import 'package:qaq_app/src/connector/ischool_plus_access_guard.dart';
import 'package:qaq_app/ui/other/msg_dialog.dart';
import 'package:qaq_app/ui/pages/webview/qaq_web_view.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:get/get.dart';
import 'package:meta/meta.dart';

@immutable
@sealed
class WebViewPage {
  @literal
  const WebViewPage();

  static const WebViewPage instance = WebViewPage();

  Future<void> close() => closeInAppWebView();

  Future<void> _launchNativeWebView({required Uri initialUrl}) async {
    try {
      final launched = await launchUrl(initialUrl, mode: LaunchMode.inAppWebView);
      if (!launched) {
        throw StateError('Unable to launch $initialUrl');
      }
    } catch (error, stackTrace) {
      stackTrace.printError();
      MsgDialog(
        MsgDialogParameter(
          desc: R.current.alertError,
          title: R.current.error,
          dialogType: DialogType.error,
          removeCancelButton: true,
          okButtonText: R.current.sure,
        ),
      ).show();
    }
  }

  Future<void> _launchQAQWebView({required Uri initialUrl, String? title}) =>
      Future.microtask(() => Get.to(() => QAQWebView(initialUrl: initialUrl, title: title)));

  /// Launch a web view with configs.
  ///
  /// Set [shouldUseAppCookies] to true if the [initialUrl] requires cookies stored in app.
  /// When [shouldUseAppCookies] is true, the internal web view will be launched,
  /// otherwise we use the native web view.
  Future<void> call({required Uri initialUrl, String? title, bool shouldUseAppCookies = false}) async {
    // Direct iStudy URLs must use our controllable WebView even when automatic
    // VPN is enabled; native LaunchMode.inAppWebView cannot be switched onto
    // the userspace GlobalProtect bridge. SSO entry URLs that can redirect to
    // iStudy already pass shouldUseAppCookies=true from SubSystemPage.
    if (IStudyAccessGuard.isIStudyUri(initialUrl) || shouldUseAppCookies) {
      return _launchQAQWebView(initialUrl: initialUrl, title: title);
    }

    return _launchNativeWebView(initialUrl: initialUrl);
  }
}
