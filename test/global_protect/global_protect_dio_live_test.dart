import 'dart:io';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qaq_app/src/connector/global_protect/global_protect_connector.dart';
import 'package:qaq_app/src/connector/global_protect/global_protect_dio_adapter.dart';
import 'package:qaq_app/src/connector/global_protect/global_protect_http_client.dart';
import 'package:qaq_app/src/connector/global_protect/global_protect_models.dart';
import 'package:qaq_app/src/connector/http_client_adapter.dart';
import 'package:qaq_app/src/connector/ischool_plus_access_guard.dart';
import 'package:qaq_app/src/connector/ischool_plus_connector.dart';
import 'package:qaq_app/src/connector/network.dart';

void main() {
  final account = Platform.environment['GP_USERNAME'];
  final password = Platform.environment['GP_PASSWORD'];
  test(
    'portal cookies and iSchool OAuth redirects work through the Dio GP adapter',
    () async {
      final connector = GlobalProtectConnector();
      final previousAdapter = dio.httpClientAdapter;
      GlobalProtectConnection? connection;
      GlobalProtectHttpClient? tunnel;
      final adapter = GlobalProtectDioAdapter(
        directAdapter: createPlatformHttpClientAdapter(),
        resolveRoute: () async => IStudyAccessRoute.vpn,
        tunnelClient: () async {
          connection ??= await connector.connectWithPassword(username: account!, password: password!);
          tunnel ??= GlobalProtectHttpClient.fromConnection(connection!);
          return tunnel!.client;
        },
      );
      dio.httpClientAdapter = adapter;
      configureNetwork(cookies: CookieJar());
      try {
        final login = await dio.post<String>(
          'https://nportal.ntut.edu.tw/login.do',
          data: {'muid': account, 'mpassword': password},
          options: Options(headers: {'user-agent': 'Direk android App'}),
        );
        expect(login.statusCode, 200);
        await cookieJar.saveFromResponse(Uri.parse('https://nportal.ntut.edu.tw/'), [
          Cookie('muid', account!.toLowerCase())..path = '/',
        ]);
        expect(await ISchoolPlusConnector.login(account), ISchoolPlusConnectorStatus.loginSuccess);
        final response = await dio.get<String>('https://istudy.ntut.edu.tw/learn/mooc_sysbar.php');
        expect(response.statusCode, 200);
        expect(response.data, isNotEmpty);
        expect(response.realUri.path, '/learn/mooc_sysbar.php');
        // Emit no body, query strings or cookies from authenticated responses.
        stdout.writeln('[HTTP] iSchool SSO + course page via Dio/GP: ${response.statusCode}');
      } finally {
        dio.httpClientAdapter = previousAdapter;
        adapter.close(force: true);
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
