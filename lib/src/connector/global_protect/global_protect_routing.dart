enum IStudyAccessRoute { direct, blocked, vpn }

class IStudyAccessBlockedException implements Exception {
  const IStudyAccessBlockedException([this.message = 'iStudy is unreachable and automatic VPN is disabled.']);
  final String message;

  @override
  String toString() => message;
}

/// Shared host policy for Dio and platform WebView proxy configuration.
class GlobalProtectRouting {
  GlobalProtectRouting._();

  static const portalHost = 'nportal.ntut.edu.tw';
  static const studyHosts = <String>['istudy.ntut.edu.tw', 'istudycloud.ntut.edu.tw'];
  // CONNECT exposes only the host, so an active WebView VPN flow also allows
  // the portal through the proxy for the iSchool SSO redirect chain.
  static const webViewProxyHosts = <String>[...studyHosts, portalHost];

  static String normalizeHost(String host) => host.toLowerCase().replaceFirst(RegExp(r'\.$'), '');

  static bool isStudyHost(String host) => studyHosts.contains(normalizeHost(host));

  static bool isStudySso(Uri uri) =>
      normalizeHost(uri.host) == portalHost &&
      uri.path == '/ssoIndex.do' &&
      const {'ischool_plus', 'ischool_plus_oauth'}.contains(uri.queryParameters['apOu']);

  static bool requiresStudyRoute(Uri uri, {String? ssoRedirectUri}) {
    if (isStudyHost(uri.host) || isStudySso(uri)) return true;
    // The measured OAuth form includes redirect_uri rather than apOu.
    final destination = ssoRedirectUri == null ? null : Uri.tryParse(ssoRedirectUri);
    return normalizeHost(uri.host) == portalHost &&
        uri.path == '/oauth2Server.do' &&
        destination != null &&
        isStudyHost(destination.host);
  }
}
