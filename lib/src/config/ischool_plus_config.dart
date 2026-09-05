class ISchoolPlusConfig {
  ISchoolPlusConfig._();

  static const String originalHost = 'istudy.ntut.edu.tw';
  static const String proxyHost = '3octcs30zx39wgdfohjaoqucyzeder4.umeow.eu.org';
  static const String proxyBaseUrl = 'https://$proxyHost/';

  static bool shouldRewrite(Uri url) =>
      (url.scheme == 'http' || url.scheme == 'https') && url.host.toLowerCase() == originalHost;

  static Uri rewriteToProxy(Uri url) {
    if (!shouldRewrite(url)) return url;

    return url.replace(scheme: 'https', host: proxyHost, port: 443);
  }

  static String rewriteUrlToProxy(String url) {
    final parsedUrl = Uri.tryParse(url);
    if (parsedUrl == null) return url;
    return rewriteToProxy(parsedUrl).toString();
  }
}
