import 'package:flutter_app/src/connector/campus_network_detector.dart';
import 'package:flutter_app/src/connector/global_protect/global_protect_debug.dart';
import 'package:flutter_app/src/r.dart';
import 'package:flutter_app/src/store/local_storage.dart';

export 'package:flutter_app/src/connector/campus_network_detector.dart';

enum IStudyAccessRoute { direct, blocked, vpn }

class IStudyAccessBlockedException implements Exception {
  const IStudyAccessBlockedException();

  @override
  String toString() => IStudyAccessGuard.blockedMessage;
}

class IStudyAccessGuard {
  IStudyAccessGuard._();

  static const iStudyHost = 'istudy.ntut.edu.tw';

  static bool isIStudyUri(Uri uri) => uri.host.toLowerCase() == iStudyHost;

  static bool isIStudyUrl(String url) {
    final uri = Uri.tryParse(url);
    return uri != null && isIStudyUri(uri);
  }

  /// Decides how an iStudy request should leave the app.
  ///
  /// Unknown public-IP state intentionally fails open and uses the normal
  /// network path. This avoids blocking users merely because the IP check
  /// service is unavailable.
  static Future<IStudyAccessRoute> route() async {
    final campus = await CampusNetworkDetector.detect();
    final autoConnectVpn = LocalStorage.instance.getOtherSetting().autoConnectIStudyVpn;
    final result = routeFor(campus, autoConnectVpn: autoConnectVpn);
    GlobalProtectDebug.log(
      'iStudy route campus=${campus.name} autoVpn=$autoConnectVpn -> ${result.name}',
    );
    return result;
  }

  static IStudyAccessRoute routeFor(
    CampusNetworkStatus campus, {
    required bool autoConnectVpn,
  }) {
    if (campus != CampusNetworkStatus.offCampus) {
      return IStudyAccessRoute.direct;
    }
    return autoConnectVpn ? IStudyAccessRoute.vpn : IStudyAccessRoute.blocked;
  }

  static Future<bool> shouldBlock() async => await route() == IStudyAccessRoute.blocked;

  static Future<bool> shouldUseVpn() async => await route() == IStudyAccessRoute.vpn;

  static Future<bool> shouldBlockUri(Uri uri) async => isIStudyUri(uri) && await shouldBlock();

  static Future<void> ensureUrlAllowed(String url) async {
    if (!isIStudyUrl(url)) return;
    if (await shouldBlock()) throw const IStudyAccessBlockedException();
  }

  static String get blockedTitle => R.current.iStudyNetworkUnavailableTitle;

  static String get blockedMessage => R.current.iStudyNetworkUnavailableMessage;

  static String get blockedHtml => _messageHtml(blockedTitle, blockedMessage);

  static String vpnFailedHtml([Object? error]) => _messageHtml(
    'VPN 連線失敗',
    '目前無法透過實驗性 VPN 連線至 i 學員。\n\n'
        '請確認帳號密碼仍可登入校務系統，或稍後重試。\n\n'
        '⚠️ 此功能仍在實驗階段，目前測試樣本有限，穩定性可能因網路環境而異。',
  );

  static String _messageHtml(String title, String message) => '''<!doctype html>
<html lang="zh-Hant">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<style>
  :root { color-scheme: light dark; }
  body { margin: 0; font-family: sans-serif; background: Canvas; color: CanvasText; }
  .wrap { min-height: 100vh; box-sizing: border-box; display: flex; align-items: center; justify-content: center; padding: 28px; }
  .card { width: min(560px, 100%); border: 1px solid color-mix(in srgb, CanvasText 16%, transparent); border-radius: 18px; padding: 24px; box-sizing: border-box; }
  h1 { font-size: 22px; margin: 0 0 14px; }
  p { font-size: 16px; line-height: 1.7; margin: 0; white-space: pre-line; }
</style>
</head>
<body>
<div class="wrap"><div class="card">
<h1>${_escapeHtml(title)}</h1>
<p>${_escapeHtml(message)}</p>
</div></div>
</body>
</html>''';

  static String _escapeHtml(String value) => value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&#39;');
}
