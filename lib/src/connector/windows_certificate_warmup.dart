import 'dart:async';
import 'dart:io';

import 'package:qaq_app/debug/log/log.dart';
import 'package:win_http/win_http.dart';

class WindowsCertificateWarmup {
  static const portalHost = 'nportal.ntut.edu.tw';
  static final Uri _portalUri = Uri.https(portalHost, '/');
  static Future<void>? _warmupFuture;

  static Future<void> ensure() {
    if (!Platform.isWindows) {
      return Future<void>.value();
    }

    return _warmupFuture ??= _warmUp();
  }

  static Future<void> _warmUp() async {
    final client = WinHttpClient.defaultConfiguration();
    try {
      final response = await client.head(_portalUri).timeout(const Duration(seconds: 5));
      Log.d('Windows certificate warm-up completed: HTTP ${response.statusCode}');
    } catch (error) {
      // Best effort only. The actual Dio request should still decide whether
      // the portal is reachable and surface its normal error handling.
      Log.d('Windows certificate warm-up skipped: $error');
    } finally {
      client.close();
    }
  }
}
