import 'package:flutter/foundation.dart';
import 'package:flutter_app/debug/log/log.dart';

/// Debug-only diagnostics for the experimental in-app GlobalProtect bridge.
///
/// Never log passwords, auth cookies, request bodies, or tunnel query values.
class GlobalProtectDebug {
  GlobalProtectDebug._();

  static void log(String message) {
    if (!kDebugMode) return;
    final line = '[GP-APP] $message';
    debugPrint(line);
    Log.d(line);
  }

  static void error(String stage, Object error, StackTrace stackTrace) {
    if (!kDebugMode) return;
    final line = '[GP-APP] ERROR $stage: ${_sanitize(error.toString())}';
    debugPrint(line);
    debugPrintStack(stackTrace: stackTrace);
    Log.eWithStack(line, stackTrace);
  }

  static String _sanitize(String value) {
    var result = value;
    for (final key in <String>[
      'passwd',
      'password',
      'authcookie',
      'portal-userauthcookie',
      'portal-prelogonuserauthcookie',
      'user',
    ]) {
      result = result.replaceAll(RegExp('($key=)[^&\\s<]+', caseSensitive: false), r'$1<redacted>');
      result = result.replaceAll(RegExp('(<$key>)[^<]*(</$key>)', caseSensitive: false), r'$1<redacted>$2');
    }
    return result;
  }
}
