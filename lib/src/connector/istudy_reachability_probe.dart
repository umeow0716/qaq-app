import 'dart:async';
import 'dart:io';

/// Checks whether iStudy is directly reachable without sending an HTTP request.
///
/// Off-campus access is silently dropped by the school network policy, so a
/// short TCP connection attempt is enough to choose between direct access and
/// the app-managed GlobalProtect transport. The result is cached briefly to
/// avoid opening a probe socket for every iStudy request.
class IStudyReachabilityProbe {
  IStudyReachabilityProbe._();

  static const host = 'istudy.ntut.edu.tw';
  static const port = 443;
  static const timeout = Duration(milliseconds: 1200);
  static const cacheDuration = Duration(seconds: 30);

  static bool? _cachedReachable;
  static DateTime? _cachedAt;
  static Future<bool>? _inFlight;

  static Future<bool> canReachDirectly() async {
    final now = DateTime.now();
    final cachedAt = _cachedAt;
    final cachedReachable = _cachedReachable;
    if (cachedAt != null && cachedReachable != null && now.difference(cachedAt) < cacheDuration) {
      return cachedReachable;
    }

    final existing = _inFlight;
    if (existing != null) return existing;

    final probe = _probe();
    _inFlight = probe;
    try {
      final reachable = await probe;
      _cachedReachable = reachable;
      _cachedAt = DateTime.now();
      return reachable;
    } finally {
      if (identical(_inFlight, probe)) _inFlight = null;
    }
  }

  static Future<bool> _probe() async {
    Socket? socket;
    try {
      socket = await Socket.connect(host, port, timeout: timeout);
      return true;
    } on SocketException {
      return false;
    } on TimeoutException {
      return false;
    } finally {
      socket?.destroy();
    }
  }

  static void clearCache() {
    _cachedReachable = null;
    _cachedAt = null;
  }
}
