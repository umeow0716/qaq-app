import 'dart:io';

import 'package:flutter/services.dart';
import 'package:qaq_app/src/config/app_config.dart';
import 'package:webview_all/webview_all.dart';
// ignore: depend_on_referenced_packages
import 'package:webview_all_windows/webview_all_windows.dart' as windows_webview;

/// Cookie bridge shared by QAQ's WebViews.
///
/// The common WebView cookie API exposes only name/value/domain/path when
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

    if (Platform.isWindows &&
        _manager.platform is windows_webview.WindowsWebViewCookieManager) {
      final manager =
          _manager.platform as windows_webview.WindowsWebViewCookieManager;
      await manager.setWindowsCookie(
        windows_webview.WindowsWebViewCookie(
          name: cookie.name,
          value: cookie.value,
          domain: _effectiveDomain(cookie, url),
          path: _effectivePath(cookie),
          expires: cookie.expires,
          isHttpOnly: cookie.httpOnly,
          isSecure: cookie.secure,
          sameSite: _windowsSameSite(cookie.sameSite),
        ),
      );
      return;
    }

    await _manager.setCookie(
      WebViewCookie(
        name: cookie.name,
        value: cookie.value,
        domain: _effectiveDomain(cookie, url),
        path: _effectivePath(cookie),
      ),
    );
  }

  static String _effectiveDomain(Cookie cookie, Uri url) {
    final domain = cookie.domain;
    return domain == null || domain.isEmpty ? url.host : domain;
  }

  static String _effectivePath(Cookie cookie) {
    final path = cookie.path;
    return path == null || path.isEmpty ? '/' : path;
  }

  static windows_webview.WindowsWebViewCookieSameSite? _windowsSameSite(
    SameSite? sameSite,
  ) {
    return switch (sameSite) {
      SameSite.none => windows_webview.WindowsWebViewCookieSameSite.none,
      SameSite.lax => windows_webview.WindowsWebViewCookieSameSite.lax,
      SameSite.strict => windows_webview.WindowsWebViewCookieSameSite.strict,
      null => null,
      _ => null,
    };
  }

  static Future<String?> cookieHeaderFor(Uri url) async {
    final cookies = await _manager.getCookies(domain: url);
    if (cookies.isEmpty) return null;
    return cookies.map((cookie) => '${cookie.name}=${cookie.value}').join('; ');
  }

  static Future<List<String>> debugLabels(Uri url) async {
    final cookies = await _manager.getCookies(domain: url);
    return cookies.map((cookie) => '${cookie.name}@${cookie.domain}${cookie.path}').toList(growable: false);
  }
}
