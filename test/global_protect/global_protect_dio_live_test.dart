import 'dart:convert';
import 'dart:io';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/io.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qaq_app/src/connector/global_protect/global_protect_app_session.dart';
import 'package:qaq_app/src/connector/global_protect/global_protect_connector.dart';
import 'package:qaq_app/src/connector/global_protect/global_protect_dio_adapter.dart';
import 'package:qaq_app/src/connector/global_protect/global_protect_http_client.dart';
import 'package:qaq_app/src/connector/global_protect/global_protect_models.dart';
import 'package:qaq_app/src/connector/global_protect/global_protect_proxy.dart';
import 'package:qaq_app/src/connector/global_protect/global_protect_routing.dart';
import 'package:qaq_app/src/connector/http_client_adapter.dart';
import 'package:qaq_app/src/connector/ischool_plus_connector.dart';
import 'package:qaq_app/src/connector/network.dart';
import 'package:qaq_app/src/connector/ntut_connector.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
    const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
    (_) async => null,
  );
  final account = Platform.environment['GP_USERNAME'];
  final password = Platform.environment['GP_PASSWORD'];
  for (final viaSharedProxy in [false, if (Platform.isWindows || Platform.isLinux) true]) {
    test(
      'portal cookies and iSchool OAuth redirects work through ${viaSharedProxy ? 'shared WebView proxy policy' : 'Dio GP routing'}',
      () async {
        HttpOverrides.global = null;
        final connector = GlobalProtectConnector();
        final nativeDesktop = Platform.isWindows || Platform.isLinux;
        GlobalProtectAppSession.instance.configureCredentials(account: () => account!, password: () => password!);
        final previousAdapter = dio.httpClientAdapter;
        GlobalProtectConnection? connection;
        GlobalProtectHttpClient? tunnel;
        final HttpClientAdapter direct;
        if (viaSharedProxy) {
          final port = await GlobalProtectProxyBridge.instance.ensureStarted(
            vpnHosts: GlobalProtectRouting.webViewProxyHosts,
          );
          direct = createDesktopProxyAdapter(port);
        } else {
          direct = createPlatformHttpClientAdapter();
        }
        final adapter = GlobalProtectDioAdapter(
          directAdapter: direct,
          resolveRoute: () async => IStudyAccessRoute.vpn,
          tunnelAdapter: () async {
            if (nativeDesktop) {
              return GlobalProtectAppSession.instance.ensureDioAdapter(
                proxyPort: () =>
                    GlobalProtectProxyBridge.instance.ensureStarted(vpnHosts: GlobalProtectRouting.webViewProxyHosts),
              );
            }
            connection ??= await connector.connectWithPassword(username: account!, password: password!);
            tunnel ??= GlobalProtectHttpClient.fromConnection(connection!);
            return IOHttpClientAdapter(createHttpClient: () => tunnel!.client);
          },
        );
        dio.httpClientAdapter = adapter;
        configureNetwork(cookies: CookieJar());
        try {
          final login = await dio.post<String>(
            'https://nportal.ntut.edu.tw/login.do',
            data: {'muid': account, 'mpassword': password},
            options: Options(
              headers: {'user-agent': 'Direk android App', 'referer': 'https://nportal.ntut.edu.tw/index.do'},
            ),
          );
          expect(login.statusCode, 200);
          expect(jsonDecode(login.data!)['success'], true);
          await cookieJar.saveFromResponse(Uri.parse('https://nportal.ntut.edu.tw/'), [
            Cookie('muid', account!.toLowerCase())..path = '/',
          ]);
          expect(await NTUTConnector.checkSession(), isTrue);
          expect(await ISchoolPlusConnector.login(account), ISchoolPlusConnectorStatus.loginSuccess);
          final response = await dio.get<String>('https://istudy.ntut.edu.tw/learn/mooc_sysbar.php');
          expect(response.statusCode, 200);
          expect(response.data, isNotEmpty);
          expect(response.realUri.path, '/learn/mooc_sysbar.php');
          expect(await NTUTConnector.checkSession(), isTrue);
          // Emit no body, query strings or cookies from authenticated responses.
          stdout.writeln('[HTTP] iSchool SSO + course page via Dio/GP: ${response.statusCode}');
        } finally {
          dio.httpClientAdapter = previousAdapter;
          adapter.close(force: true);
          await GlobalProtectAppSession.instance.disconnect();
          await GlobalProtectProxyBridge.instance.close();
          await tunnel?.close(force: true);
          await connection?.transport.close();
          connector.close();
          configureNetwork(cookies: CookieJar());
        }
      },
      skip: account == null || password == null
          ? 'Set GP_USERNAME and GP_PASSWORD to run the live Dio/GP SSO test.'
          : false,
      timeout: const Timeout(Duration(minutes: 2)),
    );
  }
}
