// ignore_for_file: import_of_legacy_library_into_null_safe

import 'package:awesome_dialog/awesome_dialog.dart';
import 'package:flutter_app/src/r.dart';
import 'package:flutter_app/ui/other/msg_dialog.dart';
import 'package:flutter_app/ui/pages/webview/tat_web_view.dart';
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
      final launched = await launchUrl(
        initialUrl,
        mode: LaunchMode.inAppWebView,
      );
      if (!launched) {
        throw StateError('Unable to launch $initialUrl');
      }
    } catch (error, stackTrace) {
      stackTrace.printError();
      MsgDialog(MsgDialogParameter(
        desc: R.current.alertError,
        title: R.current.error,
        dialogType: DialogType.error,
        removeCancelButton: true,
        okButtonText: R.current.sure,
      )).show();
    }
  }

  Future<void> _launchTATWebView({
    required Uri initialUrl,
    String? title,
  }) =>
      Future.microtask(
        () => Get.to(
          () => TATWebView(
            initialUrl: initialUrl,
            title: title,
          ),
        ),
      );

  /// Launch a web view with configs.
  ///
  /// Set [shouldUseAppCookies] to true if the [initialUrl] requires cookies stored in app.
  /// When [shouldUseAppCookies] is true, the internal web view will be launched,
  /// otherwise we use the native web view.
  Future<void> call({
    required Uri initialUrl,
    String? title,
    bool shouldUseAppCookies = false,
  }) async {
    if (shouldUseAppCookies) {
      return _launchTATWebView(
        initialUrl: initialUrl,
        title: title,
      );
    }

    return _launchNativeWebView(initialUrl: initialUrl);
  }
}
