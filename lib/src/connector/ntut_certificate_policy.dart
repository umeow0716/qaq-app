import 'dart:io';

/// App-scoped exception for NTUT endpoints whose certificate chain cannot be
/// validated by the operating system.
///
/// Keep this deliberately host-scoped: never use it as a global TLS bypass.
class NtutCertificatePolicy {
  static const String baseDomain = 'ntut.edu.tw';
  static const String _webViewSslErrorPrefix = 'SSL certificate error for ';

  static bool trustsHost(String host) {
    final normalizedHost = host.trim().toLowerCase();
    return normalizedHost == baseDomain || normalizedHost.endsWith('.$baseDomain');
  }

  static bool allowBadCertificate(X509Certificate certificate, String host, int port) {
    if (!trustsHost(host)) return false;

    // A school CA trust exception must not turn an expired or not-yet-valid
    // certificate into a valid one. dart:io does not expose the exact chain
    // verification error here, so keep the exception as narrow as the API
    // allows.
    final now = DateTime.now();
    return !now.isBefore(certificate.startValidity) && !now.isAfter(certificate.endValidity);
  }

  /// Extracts the request URI from webview_all_windows' pinned SSL error text.
  ///
  /// The Windows implementation currently reports:
  /// `SSL certificate error for <url>: <WebErrorStatus>.`
  /// Returning null keeps unknown formats fail-closed.
  static Uri? webViewRequestUri(String description) {
    if (!description.startsWith(_webViewSslErrorPrefix)) return null;

    final separator = description.lastIndexOf(': ');
    if (separator <= _webViewSslErrorPrefix.length) return null;

    return Uri.tryParse(description.substring(_webViewSslErrorPrefix.length, separator));
  }

  /// webview_all_windows maps an untrusted/invalid certificate chain to
  /// WebErrorStatusCertificateIsInvalid. Keep hostname mismatch, expiration
  /// and revocation failures fail-closed.
  static bool allowsWindowsWebViewCertificateError(String description) {
    final uri = webViewRequestUri(description);
    return uri != null && trustsHost(uri.host) && description.endsWith(': WebErrorStatusCertificateIsInvalid.');
  }
}
