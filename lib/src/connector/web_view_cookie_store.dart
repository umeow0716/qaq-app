import 'dart:io';

import 'package:flutter/services.dart';
import 'package:qaq_app/src/config/app_config.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// Cookie bridge shared by QAQ's WebViews.
///
/// webview_flutter intentionally exposes only name/value/domain/path when
/// setting a cookie. Android and iOS use a small native channel so the session
/// cookies copied from Dio also retain Secure, HttpOnly, Expires and Max-Age.
class WebViewCookieStore {
  const WebViewCookieStore._();

  static const MethodChannel _channel = MethodChannel(AppConfig.methodChannelName);
  static final WebViewCookieManager _manager = WebViewCookieManager();

  static Future<void> clearAll() async {
    await _manager.clearCookies();
  }

  static Future<void> setCookie({required Uri url, required Cookie cookie}) async {
    if (Platform.isAndroid || Platform.isIOS) {
      final stored = await _channel.invokeMethod<bool>('set_webview_cookie', <String, Object?>{
        'url': url.toString(),
        'name': cookie.name,
        'value': cookie.value,
        'domain': cookie.domain,
        'path': cookie.path ?? '/',
        'expiresDate': cookie.expires?.millisecondsSinceEpoch,
        'maxAge': cookie.maxAge,
        'isSecure': cookie.secure,
        'isHttpOnly': cookie.httpOnly,
      });
      if (stored != true) {
        throw StateError('The platform WebView rejected cookie ${cookie.name}.');
      }
      return;
    }

    await _manager.setCookie(
      WebViewCookie(
        name: cookie.name,
        value: cookie.value,
        domain: cookie.domain ?? url.host,
        path: cookie.path ?? '/',
      ),
    );
  }

  static Future<List<String>> debugLabels(Uri url) async {
    final cookies = await _manager.getCookies(domain: url);
    return cookies.map((cookie) => '${cookie.name}@${cookie.domain}${cookie.path}').toList(growable: false);
  }
}
