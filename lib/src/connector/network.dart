import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:dio_redirect_interceptor/dio_redirect_interceptor.dart';

import 'blocked_cookies.dart';
import 'global_protect/global_protect_dio_adapter.dart';
import 'global_protect/global_protect_routing.dart';
import 'http_client_adapter.dart';
import 'interceptors/request_interceptor.dart';
import 'interceptors/response_cookie_filter.dart';

export 'package:dio/dio.dart';

const presetComputerUserAgent =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/79.0.3945.79 Safari/537.36';

/// Connectors call this Dio directly. WebView and downloads share its cookies.
final Dio dio = createDio();
CookieJar _cookieJar = CookieJar();
CookieJar get cookieJar => _cookieJar;
StudyRouteResolver _studyRoute = () async => IStudyAccessRoute.blocked;
TunnelAdapterProvider _tunnelAdapter = () async => throw StateError('Network has not been initialized.');

/// Rebind persistent cookies after startup/logout without stacking interceptors.
void configureNetwork({
  required CookieJar cookies,
  StudyRouteResolver? resolveStudyRoute,
  TunnelAdapterProvider? tunnelAdapter,
}) {
  _cookieJar = cookies;
  if (resolveStudyRoute != null) _studyRoute = resolveStudyRoute;
  if (tunnelAdapter != null) _tunnelAdapter = tunnelAdapter;
  _configureInterceptors(dio, cookies);
}

/// Direct traffic uses native TLS on Android, iOS, Windows and Linux.
/// GP selects a transport adapter without nesting another Dio client.
Dio createDio({CookieJar? cookies, HttpClientAdapter? directAdapter, bool useGlobalProtect = true}) {
  final client = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 5),
      receiveTimeout: const Duration(seconds: 10),
      sendTimeout: const Duration(seconds: 5),
      headers: {HttpHeaders.userAgentHeader: presetComputerUserAgent, 'Upgrade-Insecure-Requests': '1'},
      responseType: ResponseType.plain,
      contentType: Headers.formUrlEncodedContentType,
      followRedirects: false,
      validateStatus: (status) => status != null && status >= 200 && status < 400,
    ),
  );
  client.httpClientAdapter = directAdapter ?? createPlatformHttpClientAdapter();
  if (useGlobalProtect) {
    client.httpClientAdapter = GlobalProtectDioAdapter(
      directAdapter: client.httpClientAdapter,
      resolveRoute: () => _studyRoute(),
      tunnelAdapter: () => _tunnelAdapter(),
    );
  }
  client.transformer = CampusResponseTransformer();
  _configureInterceptors(client, cookies ?? cookieJar);
  return client;
}

void _configureInterceptors(Dio client, CookieJar cookies) {
  client.interceptors
    ..clear()
    ..addAll([
      ResponseCookieFilter(blockedCookieNamePatterns: blockedCookieNamePatterns),
      CookieManager(cookies),
      RequestInterceptors(),
      RedirectInterceptor(() => client, onRedirect: _upgradeCampusRedirect),
    ]);
}

// APS still redirects its HTTPS OAuth callback to an http:// course page.
// Keep campus redirects on HTTPS before RedirectInterceptor checks downgrades.
// Other domains retain the interceptor's default downgrade protection.
bool _upgradeCampusRedirect(Response response, ResponseInterceptorHandler handler) {
  final locations = response.headers[HttpHeaders.locationHeader];
  if (locations == null || locations.length != 1) return true;
  final source = response.requestOptions.uri;
  final destination = source.resolve(locations.single);
  if (source.scheme == 'https' &&
      source.host.endsWith('.ntut.edu.tw') &&
      destination.scheme == 'http' &&
      destination.host.endsWith('.ntut.edu.tw')) {
    response.headers.set(HttpHeaders.locationHeader, destination.replace(scheme: 'https').toString());
  }
  return true;
}

/// iSchool returns malformed MIME headers. Decode plain text without parsing
/// Content-Type, while preserving Dio's byte/stream and custom decoder paths.
class CampusResponseTransformer extends BackgroundTransformer {
  @override
  Future<dynamic> transformResponse(RequestOptions options, ResponseBody responseBody) async {
    if (options.responseType == ResponseType.stream) return responseBody;
    final buffer = BytesBuilder(copy: false);
    await for (final chunk in responseBody.stream) {
      buffer.add(chunk);
    }
    final bytes = buffer.takeBytes();
    if (options.responseType == ResponseType.bytes) return bytes;
    final decoder = options.responseDecoder;
    final text = decoder == null
        ? utf8.decode(bytes, allowMalformed: true)
        : await decoder(bytes, options, responseBody);
    if (options.responseType == ResponseType.json && text != null && text.isNotEmpty) return jsonDecode(text);
    return text;
  }
}

Future<Map<String, String>> getLoginHeaders(String url) async {
  final headers = dio.options.headers.map((key, value) => MapEntry(key, value.toString()));
  final cookies = await cookieJar.loadForRequest(Uri.parse(url));
  headers.remove(HttpHeaders.contentTypeHeader);
  headers.remove(HttpHeaders.cookieHeader);
  if (cookies.isNotEmpty) {
    headers[HttpHeaders.cookieHeader] = cookies.map((cookie) => '${cookie.name}=${cookie.value}').join('; ');
  }
  return headers;
}
