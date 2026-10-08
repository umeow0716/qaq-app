import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/io.dart';
import 'package:dio_redirect_interceptor/dio_redirect_interceptor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:native_dio_adapter_desktop/native_dio_adapter_desktop.dart';
import 'package:qaq_app/src/connector/global_protect/global_protect_dio_adapter.dart';
import 'package:qaq_app/src/connector/global_protect/global_protect_routing.dart';
import 'package:qaq_app/src/connector/http_client_adapter.dart';
import 'package:qaq_app/src/connector/ischool_plus_access_guard.dart';
import 'package:qaq_app/src/connector/network.dart';

class RecordingAdapter implements HttpClientAdapter {
  RecordingAdapter(this.respond);
  final FutureOr<ResponseBody> Function(RequestOptions) respond;
  final requests = <RequestOptions>[];
  bool closed = false;

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? body, Future<void>? cancel) async {
    requests.add(options);
    return respond(options);
  }

  @override
  void close({bool force = false}) => closed = true;
}

void main() {
  test('Windows and Linux use native desktop TLS', () {
    final adapter = createPlatformHttpClientAdapter();
    addTearDown(adapter.close);
    expect(adapter, isA<NativeDesktopAdapter>());
  }, skip: !Platform.isWindows && !Platform.isLinux);

  test('normal hosts bypass route lookup even with study redirect data', () async {
    final direct = RecordingAdapter((_) => ResponseBody.fromString('direct', 200));
    var lookups = 0;
    final adapter = GlobalProtectDioAdapter(
      directAdapter: direct,
      resolveRoute: () async {
        lookups++;
        return IStudyAccessRoute.blocked;
      },
    );
    final client = createDio(directAdapter: adapter, useGlobalProtect: false, cookies: CookieJar());
    addTearDown(client.close);
    final response = await client.post<String>(
      'https://example.com/',
      data: {'redirect_uri': 'https://istudy.ntut.edu.tw/login2.php'},
    );
    expect(response.data, 'direct');
    await client.post<String>(
      'https://nportal.ntut.edu.tw/oauth2Server.do',
      data: {'redirect_uri': 'https://aps-course.ntut.edu.tw/StuQuery/LoginOAuth.jsp'},
    );
    await client.get<String>('https://nportal.ntut.edu.tw/ssoIndex.do?apOu=aa_003_LB_oauth');
    expect(lookups, 0);
  });

  test('blocked study and iSchool SSO requests never reach direct adapter', () async {
    final direct = RecordingAdapter((_) => ResponseBody.fromString('unexpected', 200));
    final adapter = GlobalProtectDioAdapter(directAdapter: direct, resolveRoute: () async => IStudyAccessRoute.blocked);
    final client = createDio(directAdapter: adapter, useGlobalProtect: false, cookies: CookieJar());
    addTearDown(client.close);
    for (final url in [
      'https://istudy.ntut.edu.tw/',
      'https://ISTUDYCLOUD.NTUT.EDU.TW./file',
      'https://istudycloud.ntut.edu.tw/',
      'https://nportal.ntut.edu.tw/ssoIndex.do?apOu=ischool_plus_oauth',
    ]) {
      await expectLater(
        client.get<String>(url),
        throwsA(isA<DioException>().having((error) => error.error, 'cause', isA<IStudyAccessBlockedException>())),
      );
    }
    await expectLater(
      client.post<String>(
        'https://nportal.ntut.edu.tw/oauth2Server.do',
        data: {'redirect_uri': 'https://istudy.ntut.edu.tw/login2.php'},
      ),
      throwsA(isA<DioException>()),
    );
    expect(direct.requests, isEmpty);
  });

  test('redirect from portal to study rechecks GP policy', () async {
    final direct = RecordingAdapter(
      (_) => ResponseBody.fromString(
        '',
        302,
        headers: {
          HttpHeaders.locationHeader: ['https://istudy.ntut.edu.tw/login2.php'],
        },
      ),
    );
    var lookups = 0;
    final adapter = GlobalProtectDioAdapter(
      directAdapter: direct,
      resolveRoute: () async {
        lookups++;
        return IStudyAccessRoute.blocked;
      },
    );
    final client = createDio(directAdapter: adapter, useGlobalProtect: false, cookies: CookieJar());
    addTearDown(client.close);
    await expectLater(client.post<String>('https://nportal.ntut.edu.tw/oauth2Server.do'), throwsA(isA<DioException>()));
    expect(direct.requests, hasLength(1));
    expect(lookups, 1);
  });

  test('VPN uses the session client and closing Dio does not close that client', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      request.response.write('tunnel');
      await request.response.close();
    });
    final tunnel = HttpClient()..findProxy = (_) => 'PROXY 127.0.0.1:${server.port}';
    addTearDown(() => tunnel.close(force: true));
    final direct = RecordingAdapter((_) => ResponseBody.fromString('direct', 200));
    var provided = 0;
    final adapter = GlobalProtectDioAdapter(
      directAdapter: direct,
      resolveRoute: () async => IStudyAccessRoute.vpn,
      tunnelAdapter: () async {
        provided++;
        return IOHttpClientAdapter(createHttpClient: () => tunnel);
      },
    );
    final client = createDio(directAdapter: adapter, useGlobalProtect: false, cookies: CookieJar());
    expect((await client.get<String>('http://istudy.ntut.edu.tw/first')).data, 'tunnel');
    expect((await client.get<String>('http://istudycloud.ntut.edu.tw/second')).data, 'tunnel');
    expect(provided, 2);
    expect(direct.requests, isEmpty);
    client.close(force: true);
    expect(direct.closed, isTrue);
    final request = await tunnel.getUrl(Uri.parse('http://istudy.ntut.edu.tw/still-open'));
    final response = await request.close();
    expect(await utf8.decoder.bind(response).join(), 'tunnel');
  });

  test('cancellation during GP route lookup prevents connecting or sending', () async {
    final lookupStarted = Completer<void>();
    final lookup = Completer<IStudyAccessRoute>();
    var tunnelRequested = false;
    final direct = RecordingAdapter((_) => ResponseBody.fromString('unexpected', 200));
    final adapter = GlobalProtectDioAdapter(
      directAdapter: direct,
      resolveRoute: () {
        lookupStarted.complete();
        return lookup.future;
      },
      tunnelAdapter: () async {
        tunnelRequested = true;
        throw StateError('unexpected');
      },
    );
    final client = createDio(directAdapter: adapter, useGlobalProtect: false, cookies: CookieJar());
    addTearDown(client.close);
    final token = CancelToken();
    final request = client.get<String>('https://istudy.ntut.edu.tw/', cancelToken: token);
    final failed = expectLater(
      request,
      throwsA(isA<DioException>().having((error) => error.type, 'type', DioExceptionType.cancel)),
    );
    await lookupStarted.future;
    token.cancel();
    await failed;
    lookup.complete(IStudyAccessRoute.vpn);
    await Future<void>.delayed(Duration.zero);
    expect(tunnelRequested, isFalse);
    expect(direct.requests, isEmpty);
  });

  test('cookies are saved before redirects, native merged headers are split', () async {
    final jar = CookieJar();
    final adapter = RecordingAdapter(
      (options) => options.uri.path == '/start'
          ? ResponseBody.fromString(
              '',
              302,
              headers: {
                'location': ['/end'],
                'set-cookie': [
                  'first=one; Path=/; Expires=Wed, 09 Jun 2038 10:18:14 GMT, second=two; Path=/, bad name=x; Path=/',
                ],
              },
            )
          : ResponseBody.fromString('ok', 200),
    );
    final client = createDio(directAdapter: adapter, useGlobalProtect: false, cookies: jar);
    addTearDown(client.close);
    final response = await client.post<String>('https://example.com/start', data: {'secret': 'value'});
    expect(response.data, 'ok');
    final last = adapter.requests.last;
    expect(last.method, 'GET');
    expect(last.data, isNull);
    expect(last.headers[HttpHeaders.cookieHeader], contains('first=one'));
    expect(last.headers[HttpHeaders.cookieHeader], contains('second=two'));
    expect(last.headers[HttpHeaders.cookieHeader], isNot(contains('bad name')));
    expect(adapter.requests.first.followRedirects, isFalse);
  });

  test('cross-origin redirects load only destination cookies and strip authorization', () async {
    final jar = CookieJar();
    await jar.saveFromResponse(Uri.parse('https://destination.example/'), [Cookie('target', 'yes')..path = '/']);
    final adapter = RecordingAdapter(
      (options) => options.uri.host == 'source.example'
          ? ResponseBody.fromString(
              '',
              302,
              headers: {
                'location': ['https://destination.example/end'],
              },
            )
          : ResponseBody.fromString('ok', 200),
    );
    final client = createDio(directAdapter: adapter, useGlobalProtect: false, cookies: jar);
    addTearDown(client.close);
    await client.get<String>(
      'https://source.example/start',
      options: Options(headers: {'authorization': 'secret', 'cookie': 'source=secret'}),
    );
    expect(adapter.requests.last.headers['authorization'], isNull);
    expect(adapter.requests.last.headers['cookie'], 'target=yes');
  });

  test('legacy APS HTTP redirects are upgraded to HTTPS', () async {
    final adapter = RecordingAdapter(
      (options) => options.uri.path == '/start'
          ? ResponseBody.fromString(
              '',
              302,
              headers: {
                'location': ['http://aps.ntut.edu.tw/course/tw/course.jsp'],
              },
            )
          : ResponseBody.fromString('ok', 200),
    );
    final client = createDio(directAdapter: adapter, useGlobalProtect: false, cookies: CookieJar());
    addTearDown(client.close);
    await client.get<String>('https://aps.ntut.edu.tw/start');
    expect(adapter.requests.last.uri.toString(), 'https://aps.ntut.edu.tw/course/tw/course.jsp');
  });

  test('307 preserves method and form body; an explicit raw redirect exposes Location', () async {
    final adapter = RecordingAdapter(
      (options) => options.uri.path == '/start'
          ? ResponseBody.fromString(
              '',
              307,
              headers: {
                'location': ['/end'],
              },
            )
          : ResponseBody.fromString('ok', 200),
    );
    final client = createDio(directAdapter: adapter, useGlobalProtect: false, cookies: CookieJar());
    addTearDown(client.close);
    await client.post<String>('https://example.com/start', data: {'code': 'test'});
    expect(adapter.requests.last.method, 'POST');
    expect(adapter.requests.last.data, {'code': 'test'});
    final raw = await client.get<String>(
      'https://example.com/start',
      options: Options(extra: {RedirectInterceptor.followRedirects: false}),
    );
    expect(raw.statusCode, 307);
    expect(raw.headers.value('location'), '/end');
  });

  test('malformed MIME headers do not break UTF-8 HTML, bytes or streams', () async {
    final adapter = RecordingAdapter(
      (_) => ResponseBody.fromBytes(
        utf8.encode("中文"),
        200,
        headers: {
          'content-type': ['text/html;;charset=UTF-8'],
        },
      ),
    );
    final client = createDio(directAdapter: adapter, useGlobalProtect: false, cookies: CookieJar());
    addTearDown(client.close);
    expect((await client.get<String>('https://example.com/')).data, '中文');
    expect(
      (await client.get<List<int>>('https://example.com/', options: Options(responseType: ResponseType.bytes))).data,
      utf8.encode("中文"),
    );
    final stream = await client.get<ResponseBody>(
      'https://example.com/',
      options: Options(responseType: ResponseType.stream),
    );
    expect(await stream.data!.stream.expand((chunk) => chunk).toList(), utf8.encode("中文"));
    expect((await client.get<String>('https://example.com/')).data, isA<String>());
  });

  test('HTTP errors fail instead of feeding an error page into parsers', () async {
    final adapter = RecordingAdapter((_) => ResponseBody.fromString('failure', 500));
    final client = createDio(directAdapter: adapter, useGlobalProtect: false, cookies: CookieJar());
    addTearDown(client.close);
    await expectLater(
      client.get<String>('https://example.com/'),
      throwsA(isA<DioException>().having((error) => error.type, 'type', DioExceptionType.badResponse)),
    );
  });

  test('concurrent requests use independent Referer defaults and remove null Cookie', () async {
    final adapter = RecordingAdapter((_) => ResponseBody.fromString('ok', 200));
    final client = createDio(directAdapter: adapter, useGlobalProtect: false, cookies: CookieJar());
    addTearDown(client.close);
    await Future.wait([client.get<String>('https://example.com/one'), client.get<String>('https://example.com/two')]);
    for (final request in adapter.requests) {
      expect(request.headers['referer'], 'https://nportal.ntut.edu.tw/');
      expect(request.headers.containsKey('cookie'), isFalse);
    }
  });

  test('network reconfiguration replaces cookie interceptors without duplication', () {
    configureNetwork(cookies: CookieJar());
    final count = dio.interceptors.length;
    configureNetwork(cookies: CookieJar());
    expect(dio.interceptors.length, count);
    expect(dio.interceptors.whereType<RedirectInterceptor>(), hasLength(1));
  });
}
